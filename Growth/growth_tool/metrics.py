import csv
from collections import defaultdict
from pathlib import Path

from .common import normalize_header, parse_iso_date, parse_number, round_number, sha256_file, utc_now, write_csv, write_json


def _column_map(fieldnames, aliases):
    normalized = {normalize_header(name): name for name in fieldnames}
    result = {}
    for metric, candidates in aliases.items():
        for candidate in candidates:
            found = normalized.get(normalize_header(candidate))
            if found:
                result[metric] = found
                break
    return result


def _ratio(numerator, denominator):
    if numerator is None or denominator is None or denominator <= 0:
        return None
    return numerator / denominator


def _decision(metrics, config):
    thresholds = config["decision_thresholds"]
    conversion_metric = next((name for name in thresholds["conversion_metric_priority"] if name in metrics), None)
    signals = {}
    if conversion_metric:
        signals["conversion"] = {"metric": conversion_metric, "value": metrics[conversion_metric]}
    for name in ("retention_day_30", "payback_days"):
        if name in metrics:
            signals[name] = {"metric": name, "value": metrics[name]}
    if not signals:
        return {
            "decision": "INSUFFICIENT_DATA",
            "reasons": ["None of the configured conversion, day-30 retention, or payback decision signals are available."],
            "signals_used": {},
        }
    stop_reasons = []
    scale_checks = {}
    if conversion_metric:
        value = metrics[conversion_metric]
        if value < float(thresholds["conversion"]["stop_below"]):
            stop_reasons.append("{} is below the stop threshold.".format(conversion_metric))
        scale_checks["conversion"] = value >= float(thresholds["conversion"]["scale_at_or_above"])
    if "retention_day_30" in metrics:
        value = metrics["retention_day_30"]
        if value < float(thresholds["retention_day_30"]["stop_below"]):
            stop_reasons.append("retention_day_30 is below the stop threshold.")
        scale_checks["retention_day_30"] = value >= float(thresholds["retention_day_30"]["scale_at_or_above"])
    if "payback_days" in metrics:
        value = metrics["payback_days"]
        if value > float(thresholds["payback_days"]["stop_above"]):
            stop_reasons.append("payback_days is above the stop threshold.")
        scale_checks["payback_days"] = value <= float(thresholds["payback_days"]["scale_at_or_below"])
    if stop_reasons:
        decision = "STOP"
        reasons = stop_reasons
    elif len(signals) >= int(thresholds["minimum_scale_signals"]) and all(scale_checks.values()):
        decision = "SCALE"
        reasons = ["All {} available decision signals meet scale thresholds.".format(len(signals))]
    else:
        decision = "ITERATE"
        reasons = ["Decision data exist, but the scale requirements are not all met and no stop rule fired."]
        if len(signals) < int(thresholds["minimum_scale_signals"]):
            reasons.append("Only {} decision signal is available; at least {} are required to scale.".format(len(signals), thresholds["minimum_scale_signals"]))
    return {
        "decision": decision,
        "reasons": reasons,
        "signals_used": signals,
        "scale_checks": scale_checks,
        "stop_reasons": stop_reasons,
        "deterministic_rules": thresholds["rules"],
    }


def _calculate_group(group, config, observation_days_override=None):
    values = group["values"]
    observed = group["observed"]
    metrics = {}
    reasons = {}

    def value(name):
        return values[name] if observed[name] else None

    def ratio_metric(name, numerator, denominator):
        result = _ratio(value(numerator), value(denominator))
        if result is not None:
            metrics[name] = result
        else:
            reasons[name] = "Requires {} and a positive {} denominator with observed values.".format(numerator, denominator)

    ratio_metric("product_page_conversion", "downloads", "product_page_views")
    ratio_metric("install_to_purchase_conversion", "paying_users", "downloads")
    ratio_metric("trial_conversion", "trial_conversions", "trial_starts")
    for day in (1, 7, 30):
        ratio_metric("retention_day_{}".format(day), "retained_day_{}".format(day), "cohort_users")

    net_revenue = value("net_revenue")
    net_revenue_basis = "net_revenue column" if net_revenue is not None else None
    if net_revenue is None and observed["gross_revenue"] and observed["refunds"]:
        net_revenue = values["gross_revenue"] - abs(values["refunds"])
        net_revenue_basis = "gross_revenue - abs(refunds)"
    rpi_revenue = net_revenue
    rpi_basis = net_revenue_basis
    if rpi_revenue is None and observed["gross_revenue"]:
        rpi_revenue = values["gross_revenue"]
        rpi_basis = "gross_revenue (net revenue unavailable)"
    if rpi_revenue is not None and _ratio(rpi_revenue, value("downloads")) is not None:
        metrics["revenue_per_install"] = rpi_revenue / values["downloads"]
    else:
        reasons["revenue_per_install"] = "Requires a revenue column and a positive downloads denominator."
    plan_columns = ("monthly_subscribers", "annual_subscribers", "lifetime_subscribers")
    if all(observed[name] for name in plan_columns):
        plan_total = sum(values[name] for name in plan_columns)
        if plan_total > 0:
            metrics["annual_subscription_mix"] = values["annual_subscribers"] / plan_total
            metrics["lifetime_subscription_mix"] = values["lifetime_subscribers"] / plan_total
        else:
            reasons["annual_subscription_mix"] = "Subscription plan columns exist but their total is zero."
            reasons["lifetime_subscription_mix"] = "Subscription plan columns exist but their total is zero."
    else:
        missing = [name for name in plan_columns if not observed[name]]
        reasons["annual_subscription_mix"] = "Requires observed monthly, annual, and lifetime subscriber counts; missing {}.".format(", ".join(missing))
        reasons["lifetime_subscription_mix"] = "Requires observed monthly, annual, and lifetime subscriber counts; missing {}.".format(", ".join(missing))
    if _ratio(value("acquisition_spend"), value("paying_users")) is not None:
        metrics["customer_acquisition_cost"] = values["acquisition_spend"] / values["paying_users"]
    else:
        reasons["customer_acquisition_cost"] = "Requires acquisition_spend and a positive paying_users denominator."
    if observed["gross_revenue"] and observed["refunds"] and values["gross_revenue"] > 0:
        metrics["refund_rate"] = abs(values["refunds"]) / values["gross_revenue"]
    else:
        reasons["refund_rate"] = "Requires refunds and positive gross_revenue."
    observation_days = observation_days_override if observation_days_override is not None else group["observation_days"]
    if net_revenue is not None and net_revenue > 0 and observed["acquisition_spend"] and observation_days and observation_days > 0:
        metrics["payback_days"] = values["acquisition_spend"] / net_revenue * observation_days
    else:
        reasons["payback_days"] = "Requires positive net revenue (net/proceeds or gross revenue plus refunds), acquisition_spend, and observation days (from valid dates or --observation-days)."
    rounded = {name: round_number(value) for name, value in sorted(metrics.items())}
    return {
        "available_metrics": rounded,
        "unavailable_metrics": {name: reasons[name] for name in sorted(config["metric_formulas"]) if name not in rounded},
        "metric_units": {
            name: ("days" if name == "payback_days" else ("input_currency_per_install" if name == "revenue_per_install" else ("input_currency_per_paying_user" if name == "customer_acquisition_cost" else "ratio")))
            for name in rounded
        },
        "calculation_context": {
            "row_count": group["row_count"],
            "observation_days": observation_days,
            "net_revenue_basis": net_revenue_basis if net_revenue is not None else None,
            "revenue_per_install_basis": rpi_basis if rpi_revenue is not None else None,
            "summed_inputs": {name: round_number(values[name], 2) for name in sorted(values) if observed[name]},
        },
        "decision": _decision(rounded, config),
    }


def calculate_csv(input_path, output_dir, config, observation_days=None):
    input_path = Path(input_path)
    output_dir = Path(output_dir)
    if observation_days is not None and observation_days <= 0:
        raise ValueError("--observation-days must be positive.")
    with input_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ValueError("The launch-metrics CSV has no header row.")
        fieldnames = list(reader.fieldnames)
        columns = _column_map(fieldnames, config["column_aliases"])
        metric_columns = [name for name in config["column_aliases"] if name not in {"variant", "date"}]
        if not any(name in columns for name in metric_columns):
            raise ValueError("No recognized metric columns found. Configure column_aliases for this export.")
        groups = {}
        warnings = []
        row_count = 0
        for row_number, row in enumerate(reader, start=2):
            row_count += 1
            variant = row.get(columns["variant"], "").strip() if "variant" in columns else "all"
            variant = variant or "all"
            group = groups.setdefault(
                variant,
                {"values": defaultdict(float), "observed": defaultdict(bool), "dates": [], "row_count": 0, "observation_days": None},
            )
            group["row_count"] += 1
            if "date" in columns:
                raw_date = row.get(columns["date"])
                parsed_date = parse_iso_date(raw_date)
                if raw_date and str(raw_date).strip() and parsed_date is None:
                    warnings.append({"row": row_number, "column": columns["date"], "warning": "Ignored unrecognized date: {}".format(raw_date)})
                if parsed_date:
                    group["dates"].append(parsed_date)
            for metric in metric_columns:
                if metric not in columns:
                    continue
                raw = row.get(columns[metric])
                if raw is None or not str(raw).strip():
                    continue
                value = parse_number(raw)
                if value is None:
                    warnings.append({"row": row_number, "column": columns[metric], "warning": "Ignored unparsable numeric value: {}".format(raw)})
                    continue
                group["values"][metric] += value
                group["observed"][metric] = True
        if not groups:
            groups["all"] = {"values": defaultdict(float), "observed": defaultdict(bool), "dates": [], "row_count": 0, "observation_days": None}
        for group in groups.values():
            if group["dates"]:
                group["observation_days"] = (max(group["dates"]) - min(group["dates"])).days + 1
            del group["dates"]
    results = {variant: _calculate_group(group, config, observation_days) for variant, group in sorted(groups.items())}
    generated_at = utc_now()
    payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "generated_output_label": config["generated_output_label"],
        "input": {"path": str(input_path), "sha256": sha256_file(input_path), "row_count": row_count},
        "columns_detected": columns,
        "unrecognized_columns": [name for name in fieldnames if name not in columns.values()],
        "input_assumptions": config["input_assumptions"],
        "metric_formulas": config["metric_formulas"],
        "decision_thresholds": config["decision_thresholds"],
        "observation_days_override": observation_days,
        "groups": results,
        "warnings": warnings,
        "simulated_results": False,
    }
    if not results:
        payload["empty_input"] = "No data rows were supplied, so no metrics or decisions were computed."
    write_json(output_dir / "launch_metrics.json", payload)
    metric_rows = []
    decision_rows = []
    for variant, result in results.items():
        for metric in config["metric_formulas"]:
            available = metric in result["available_metrics"]
            metric_rows.append(
                {
                    "variant": variant,
                    "metric": metric,
                    "status": "available" if available else "unavailable",
                    "value": result["available_metrics"].get(metric),
                    "unit": result["metric_units"].get(metric),
                    "formula": config["metric_formulas"][metric],
                    "unavailable_reason": result["unavailable_metrics"].get(metric),
                }
            )
        decision_rows.append(
            {
                "variant": variant,
                "decision": result["decision"]["decision"],
                "reasons": result["decision"]["reasons"],
                "signals_used": result["decision"]["signals_used"],
                "row_count": result["calculation_context"]["row_count"],
                "observation_days": result["calculation_context"]["observation_days"],
            }
        )
    write_csv(output_dir / "launch_metrics.csv", ["variant", "metric", "status", "value", "unit", "formula", "unavailable_reason"], metric_rows)
    write_csv(output_dir / "launch_decisions.csv", ["variant", "decision", "reasons", "signals_used", "row_count", "observation_days"], decision_rows)
    return payload
