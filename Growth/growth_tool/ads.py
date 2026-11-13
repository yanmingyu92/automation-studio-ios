import csv
from collections import defaultdict
from pathlib import Path

from .common import normalize_header, parse_number, round_number, sha256_file, utc_now, write_csv, write_json


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


def _divide(numerator, denominator):
    if numerator is None or denominator is None or denominator <= 0:
        return None
    return numerator / denominator


def _rounded_increment(value, increment):
    return round(int(value / increment + 1e-9) * increment, 10)


def optimize_csv(input_path, output_dir, config):
    input_path = Path(input_path)
    output_dir = Path(output_dir)
    with input_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ValueError("The search-term CSV has no header row.")
        fieldnames = list(reader.fieldnames)
        columns = _column_map(fieldnames, config["column_aliases"])
        if "search_term" not in columns:
            raise ValueError("No search-term column found. Configure column_aliases.search_term to match this export.")
        groups = {}
        warnings = []
        row_count = 0
        for row_number, row in enumerate(reader, start=2):
            row_count += 1
            term = (row.get(columns["search_term"]) or "").strip()
            if not term:
                warnings.append({"row": row_number, "warning": "Skipped row with an empty search term."})
                continue
            key = term.casefold()
            group = groups.setdefault(
                key,
                {
                    "search_term": term,
                    "campaigns": set(),
                    "ad_groups": set(),
                    "source_match_types": set(),
                    "source_keywords": set(),
                    "source_rows": [],
                    "values": defaultdict(float),
                    "observed": defaultdict(bool),
                    "bids": [],
                },
            )
            group["source_rows"].append(row_number)
            for dimension in ("campaign", "ad_group", "match_type", "keyword"):
                if dimension in columns and row.get(columns[dimension]):
                    target = {"campaign": "campaigns", "ad_group": "ad_groups", "match_type": "source_match_types", "keyword": "source_keywords"}[dimension]
                    group[target].add(row[columns[dimension]].strip())
            for metric in ("impressions", "taps", "conversions", "spend"):
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
            if "bid" in columns:
                raw = row.get(columns["bid"])
                if raw and str(raw).strip():
                    value = parse_number(raw)
                    if value is None:
                        warnings.append({"row": row_number, "column": columns["bid"], "warning": "Ignored unparsable bid value: {}".format(raw)})
                    else:
                        group["bids"].append(value)
    total_spend = sum(group["values"]["spend"] for group in groups.values() if group["observed"]["spend"])
    budget_exhausted = "spend" in columns and total_spend >= float(config["budget_cap"])
    recommendations = []
    for key in sorted(groups):
        group = groups[key]
        values = group["values"]
        observed = group["observed"]
        impressions = values["impressions"] if observed["impressions"] else None
        taps = values["taps"] if observed["taps"] else None
        conversions = values["conversions"] if observed["conversions"] else None
        spend = values["spend"] if observed["spend"] else None
        ctr = _divide(taps, impressions)
        conversion_rate = _divide(conversions, taps)
        cpa = _divide(spend, conversions)
        current_bid = max(group["bids"]) if group["bids"] else None
        exact_action = "insufficient_evidence_keep_under_review"
        broad_action = "retain_controlled_broad_discovery"
        discovery_action = "retain_discovery_for_new_search_terms"
        bid_direction = "hold"
        reasons = []
        enough_conversions = conversions is not None and conversions >= float(config["minimum_conversions_for_exact"])
        efficient = cpa is not None and cpa <= float(config["target_cpa"])
        enough_taps = taps is not None and taps >= float(config["minimum_taps_for_conversion_assessment"])
        negative_review = (
            enough_taps
            and conversions == 0
            and spend is not None
            and spend >= float(config["minimum_spend_for_negative_review"])
        )
        if enough_conversions and efficient:
            exact_action = "graduate_to_exact_or_retain_exact"
            discovery_action = "review_negative_exact_in_discovery_after_exact_coverage_to_avoid_internal_competition"
            bid_direction = "increase"
            reasons.append("Conversion threshold met and observed CPA is at or below target.")
        elif negative_review:
            exact_action = "do_not_graduate_without_conversions"
            broad_action = "review_broad_relevance_and_reduce_bid"
            discovery_action = "review_negative_exact_candidate_no_automatic_exclusion"
            bid_direction = "decrease"
            reasons.append("Enough taps and spend with zero recorded conversions; review relevance and negative-exact eligibility.")
        elif conversions is not None and conversions > 0 and cpa is not None and cpa > float(config["target_cpa"]):
            exact_action = "controlled_exact_test_with_lower_bid"
            broad_action = "retain_broad_only_for_controlled_exploration"
            bid_direction = "decrease"
            reasons.append("Observed CPA exceeds target; do not scale.")
        elif conversions is not None and conversions > 0:
            exact_action = "exact_candidate_pending_more_efficiency_evidence"
            reasons.append("Some conversions observed, but thresholds for scaling were not met.")
        else:
            reasons.append("Insufficient conversion or spend evidence for graduation, reduction, or negative review.")
        if budget_exhausted and bid_direction == "increase":
            bid_direction = "hold"
            reasons.append("Bid increase suppressed because total CSV spend meets or exceeds the configured budget cap.")
        if ctr is not None and impressions >= float(config["minimum_impressions_for_ctr_assessment"]) and ctr < float(config["low_ctr_threshold"]):
            reasons.append("Observed CTR is below the configured review threshold; assess relevance, creative, and placement rather than pausing on CTR alone.")
        increment = float(config["bid_increment"])
        maximum_bid = float(config["maximum_bid"])
        minimum_bid = float(config["minimum_bid"])
        suggested_bid = None
        bid_change = None
        bid_change_fraction = None
        if current_bid is not None:
            if bid_direction == "increase":
                raw_change = min(current_bid * float(config["maximum_bid_increase_fraction"]), maximum_bid - current_bid)
                bid_change = max(0.0, _rounded_increment(raw_change, increment))
                suggested_bid = min(maximum_bid, current_bid + bid_change)
            elif bid_direction == "decrease":
                raw_change = min(current_bid * float(config["maximum_bid_decrease_fraction"]), current_bid - minimum_bid)
                bid_change = -max(0.0, _rounded_increment(raw_change, increment))
                suggested_bid = max(minimum_bid, current_bid + bid_change)
            else:
                bid_change = 0.0
                suggested_bid = min(maximum_bid, max(minimum_bid, current_bid))
            bid_change_fraction = _divide(bid_change, current_bid)
        recommendations.append(
            {
                "search_term": group["search_term"],
                "campaigns": sorted(group["campaigns"]),
                "ad_groups": sorted(group["ad_groups"]),
                "source_match_types": sorted(group["source_match_types"]),
                "source_keywords": sorted(group["source_keywords"]),
                "source_rows": group["source_rows"],
                "impressions": round_number(impressions, 2),
                "taps": round_number(taps, 2),
                "conversions": round_number(conversions, 2),
                "spend": round_number(spend, 2),
                "ctr": round_number(ctr),
                "conversion_rate": round_number(conversion_rate),
                "cpa": round_number(cpa, 2),
                "current_bid_conservative_max": round_number(current_bid, 2),
                "exact_match_action": exact_action,
                "broad_match_action": broad_action,
                "discovery_action": discovery_action,
                "bid_direction": bid_direction,
                "recommended_bid_change": round_number(bid_change, 2),
                "recommended_bid_change_fraction": round_number(bid_change_fraction),
                "suggested_bid": round_number(suggested_bid, 2),
                "reasons": reasons,
                "recommendation_only": True,
            }
        )
    generated_at = utc_now()
    payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "mode": "dry_run_recommendations_only",
        "no_ad_api_or_spending": True,
        "strategy": config["strategy"],
        "input": {"path": str(input_path), "sha256": sha256_file(input_path), "row_count": row_count},
        "columns_detected": columns,
        "missing_metric_columns": [name for name in ("impressions", "taps", "conversions", "spend", "bid") if name not in columns],
        "configuration": {
            key: config[key]
            for key in (
                "target_cpa", "budget_cap", "currency", "minimum_bid", "maximum_bid", "bid_increment",
                "maximum_bid_increase_fraction", "maximum_bid_decrease_fraction", "minimum_taps_for_conversion_assessment",
                "minimum_conversions_for_exact", "minimum_spend_for_negative_review", "low_ctr_threshold",
                "minimum_impressions_for_ctr_assessment", "metric_formulas", "decision_rules"
            )
        },
        "total_observed_spend": round_number(total_spend, 2) if "spend" in columns else None,
        "budget_cap_status": "met_or_exceeded_in_this_export" if budget_exhausted else ("below_cap_in_this_export" if "spend" in columns else "unavailable"),
        "recommendations": recommendations,
        "warnings": warnings,
        "limitations": [
            "This export may not represent the complete account budget or the latest auction state; verify in Apple Ads before any manual action.",
            "Attribution and conversion definitions are inherited from the CSV. No causality or future performance is inferred.",
            "Bid changes use the maximum observed bid for duplicate terms as a conservative starting point and are incremental suggestions only.",
        ],
    }
    write_json(output_dir / "apple_ads_recommendations.json", payload)
    fields = [
        "search_term", "campaigns", "ad_groups", "source_match_types", "source_keywords", "impressions", "taps", "conversions", "spend",
        "ctr", "conversion_rate", "cpa", "current_bid_conservative_max", "exact_match_action", "broad_match_action", "discovery_action",
        "bid_direction", "recommended_bid_change", "recommended_bid_change_fraction", "suggested_bid", "reasons", "recommendation_only"
    ]
    write_csv(output_dir / "apple_ads_recommendations.csv", fields, recommendations)
    write_json(output_dir / "apple_ads_summary.json", {
        "generated_at_utc": generated_at,
        "mode": "dry_run_recommendations_only",
        "input_rows": row_count,
        "search_terms": len(recommendations),
        "bid_increases": sum(item["bid_direction"] == "increase" for item in recommendations),
        "bid_decreases": sum(item["bid_direction"] == "decrease" for item in recommendations),
        "exact_graduations": sum(item["exact_match_action"] == "graduate_to_exact_or_retain_exact" for item in recommendations),
        "warning_count": len(warnings),
        "output": "No changes applied and no spending authorized.",
    })
    return payload
