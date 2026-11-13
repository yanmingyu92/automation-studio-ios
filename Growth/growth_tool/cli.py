import argparse
import sys
from pathlib import Path

from . import __version__
from .ads import optimize_csv
from .analyze import analyze
from .common import CACHE_DIR, CONFIG_DIR, OUTPUT_DIR, load_config, load_json
from .fetch import FetchFailure, PublicFetcher, discover, fetch_competitors
from .generate import generate
from .metrics import calculate_csv


def _positive_pages(value):
    parsed = int(value)
    if not 1 <= parsed <= 10:
        raise argparse.ArgumentTypeError("pages must be between 1 and 10")
    return parsed


def _positive_days(value):
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("observation days must be positive")
    return parsed


def build_parser():
    parser = argparse.ArgumentParser(
        prog="growth.py",
        description="Public-data market intelligence and recommendations-only launch experiments (Python standard library).",
        epilog=(
            "Examples:\n"
            "  python3 growth.py pipeline\n"
            "  python3 growth.py pipeline --offline\n"
            "  python3 growth.py ads --input exported_search_terms.csv\n"
            "  python3 growth.py launch-metrics --input revenuecat_export.csv --observation-days 30\n\n"
            "All generated files default to ignored Growth/Output. No publishing, ad API, user contact, or spending is performed."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", action="version", version="%(prog)s " + __version__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def network_arguments(command):
        group = command.add_mutually_exclusive_group()
        group.add_argument("--offline", action="store_true", help="Use cached public responses only; never make network requests.")
        group.add_argument("--refresh", action="store_true", help="Request fresh public responses even when cached responses exist.")
        command.add_argument("--pages", type=_positive_pages, help="Apple RSS pages per competitor (1-10; configuration default applies when omitted).")

    discover_parser = subparsers.add_parser("discover", help="Discover and rank real App Store candidates with public iTunes Search.")
    network_arguments(discover_parser)
    discover_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR / "data")

    fetch_parser = subparsers.add_parser("fetch", help="Fetch iTunes metadata and public recent-review RSS with caching and provenance.")
    network_arguments(fetch_parser)
    fetch_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR / "data")

    analyze_parser = subparsers.add_parser("analyze", help="Analyze sampled ratings, low reviews, themes, n-grams, and opportunity scores locally.")
    analyze_parser.add_argument("--input", type=Path, default=OUTPUT_DIR / "data" / "competitors.json")
    analyze_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR / "data")

    generate_parser = subparsers.add_parser("generate", help="Generate truthful ASO, custom-page, experiment, creative, and static-site deliverables.")
    generate_parser.add_argument("--input", type=Path, default=OUTPUT_DIR / "data" / "analysis.json")
    generate_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)

    pipeline_parser = subparsers.add_parser("pipeline", help="Run discover, fetch, analyze, and generate end to end.")
    network_arguments(pipeline_parser)
    pipeline_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)

    ads_parser = subparsers.add_parser(
        "ads",
        help="Dry-run Apple Ads search-term recommendations; never calls an ad API or spends money.",
        description="Read an exported Apple Ads search-term CSV. Calculate CTR, conversion rate, and CPA when source columns exist; emit recommendations only.",
    )
    ads_parser.add_argument("--input", type=Path, required=True, help="Real exported Apple Ads search-term CSV.")
    ads_parser.add_argument("--config", type=Path, default=CONFIG_DIR / "ads.json")
    ads_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR / "ads")

    for name in ("launch-metrics", "metrics"):
        metrics_parser = subparsers.add_parser(
            name,
            help="Compute available launch metrics and deterministic decisions from a real CSV export.",
            description=(
                "Read one coherent App Store Connect or RevenueCat-style CSV export. Recognized columns are configured in metrics.json. "
                "Ratios, retention, RPI, plan mix, CAC, and observation-window payback are emitted only when their inputs exist. "
                "Use --observation-days when the export has no usable date column."
            ),
        )
        metrics_parser.add_argument("--input", type=Path, required=True, help="Real App Store Connect or RevenueCat-style CSV; do not mix overlapping exports.")
        metrics_parser.add_argument("--config", type=Path, default=CONFIG_DIR / "metrics.json")
        metrics_parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR / "launch_metrics")
        metrics_parser.add_argument("--observation-days", type=_positive_days, help="Override observation-window length for payback calculations.")
    return parser


def _fetcher(config, args):
    return PublicFetcher(CACHE_DIR / "http", config["http"], offline=args.offline, refresh=args.refresh)


def _discover(args, config=None, products=None, output_dir=None):
    config = config or load_config("competitors.json")
    products = products or load_config("products.json")
    return discover(config, products, output_dir or args.output_dir, _fetcher(config, args))


def run(args):
    if args.command == "discover":
        result = _discover(args)
        print("Discovered {} candidates; selected {}.".format(len(result["candidates"]), sum(len(ids) for ids in result["selected_by_product"].values())))
        print("Output: " + str(args.output_dir))
        return 0
    if args.command == "fetch":
        config = load_config("competitors.json")
        products = load_config("products.json")
        fetcher = _fetcher(config, args)
        discovery = discover(config, products, args.output_dir, fetcher)
        result = fetch_competitors(config, discovery, args.output_dir, fetcher, pages=args.pages)
        print("Fetched {} competitors and {} deduplicated sampled reviews; {} source errors.".format(len(result["competitors"]), sum(item["sampled_review_count"] for item in result["competitors"]), len(result["errors"])))
        print("Output: " + str(args.output_dir))
        return 0 if any(item["lookup_source"].get("fetched_at_utc") for item in result["competitors"]) else 2
    if args.command == "analyze":
        result = analyze(load_json(args.input), load_config("products.json"), load_config("analysis.json"), args.output_dir, input_path=args.input)
        print("Analyzed {} products. Output: {}".format(len(result["products"]), args.output_dir))
        return 0
    if args.command == "generate":
        result = generate(load_json(args.input), load_config("products.json"), args.output_dir)
        print("Generated {} experiments and {} creative briefs. Output: {}".format(len(result["experiments"]), len(result["creative_briefs"]), args.output_dir))
        return 0
    if args.command == "pipeline":
        config = load_config("competitors.json")
        products = load_config("products.json")
        data_dir = args.output_dir / "data"
        fetcher = _fetcher(config, args)
        discovery = discover(config, products, data_dir, fetcher)
        fetched = fetch_competitors(config, discovery, data_dir, fetcher, pages=args.pages)
        if not any(item["lookup_source"].get("fetched_at_utc") for item in fetched["competitors"]):
            print("error: every competitor lookup failed; partial error output is in " + str(data_dir), file=sys.stderr)
            return 2
        analysis_path = data_dir / "competitors.json"
        analysis = analyze(fetched, products, load_config("analysis.json"), data_dir, input_path=analysis_path)
        generated = generate(analysis, products, args.output_dir)
        print("Pipeline complete: {} competitors, {} sampled reviews, {} experiments.".format(
            len(fetched["competitors"]),
            sum(item["sampled_review_count"] for item in fetched["competitors"]),
            len(generated["experiments"]),
        ))
        print("Data: " + str(data_dir))
        print("Site: " + str(args.output_dir / "site" / "index.html"))
        print("Experiments: " + str(args.output_dir / "experiments"))
        if fetched["errors"]:
            print("Completed with {} public-source errors; see {}.".format(len(fetched["errors"]), data_dir / "fetch_report.json"))
        return 0
    if args.command == "ads":
        result = optimize_csv(args.input, args.output_dir, load_json(args.config))
        print("Dry run complete: {} search terms, {} warnings. No ads changed and no money spent.".format(len(result["recommendations"]), len(result["warnings"])))
        print("Output: " + str(args.output_dir))
        return 0
    if args.command in {"launch-metrics", "metrics"}:
        result = calculate_csv(args.input, args.output_dir, load_json(args.config), observation_days=args.observation_days)
        decisions = {name: details["decision"]["decision"] for name, details in result["groups"].items()}
        print("Launch metrics complete. Decisions: " + (str(decisions) if decisions else "INSUFFICIENT_DATA (no rows)"))
        print("Output: " + str(args.output_dir))
        return 0
    raise ValueError("Unknown command: " + args.command)


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return run(args)
    except (ValueError, OSError, FetchFailure) as error:
        print("error: {}".format(error), file=sys.stderr)
        return 2
