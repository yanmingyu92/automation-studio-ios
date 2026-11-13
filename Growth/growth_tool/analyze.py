import math
import re
from collections import Counter, defaultdict
from pathlib import Path

from .common import GENERATED_LABEL, round_number, utc_now, write_csv, write_json


def _normalized_text(value):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", (value or "").casefold())).strip()


def _matches(text, phrase):
    normalized_phrase = _normalized_text(phrase)
    if not normalized_phrase:
        return False
    if len(normalized_phrase) <= 4 or normalized_phrase == "pr":
        return " {} ".format(normalized_phrase) in " {} ".format(text)
    return normalized_phrase in text


def _review_text(review):
    return _normalized_text("{} {}".format(review.get("title", ""), review.get("text", "")))


def _theme_matches(review, theme):
    text = _review_text(review)
    return [phrase for phrase in theme["phrases"] if _matches(text, phrase)]


def _ngrams(reviews, settings, maximum_ids):
    stop_words = set(settings["stop_words"])
    counts = defaultdict(set)
    for review in reviews:
        tokens = [token for token in _review_text(review).split() if token not in stop_words and not token.isdigit()]
        seen = set()
        for size in settings["sizes"]:
            for index in range(0, len(tokens) - size + 1):
                gram_tokens = tokens[index:index + size]
                if any(token in stop_words for token in gram_tokens):
                    continue
                gram = " ".join(gram_tokens)
                if gram not in seen:
                    counts[gram].add(review["review_id"])
                    seen.add(gram)
    result = []
    for gram, review_ids in counts.items():
        if len(review_ids) < int(settings["minimum_review_count"]):
            continue
        result.append(
            {
                "ngram": gram,
                "review_count": len(review_ids),
                "review_ids": sorted(review_ids)[:maximum_ids],
            }
        )
    result.sort(key=lambda item: (-item["review_count"], item["ngram"]))
    return result


def _rating_distribution(reviews):
    rated = [review for review in reviews if review.get("rating") in {1, 2, 3, 4, 5}]
    counts = Counter(review["rating"] for review in rated)
    denominator = len(rated)
    return {
        "sampled_rated_review_count": denominator,
        "counts": {str(rating): counts.get(rating, 0) for rating in range(1, 6)},
        "shares": {str(rating): round_number(counts.get(rating, 0) / denominator) if denominator else None for rating in range(1, 6)},
        "scope": "Distribution of the fetched recent-review sample only; Apple does not expose the app's full rating histogram in these endpoints.",
    }


def _unique_reviews(reviews):
    return {review["review_id"]: review for review in reviews}


def analyze(fetch_data, products_config, config, output_dir, input_path=None):
    generated_at = utc_now()
    maximum_ids = int(config["maximum_review_ids_per_item"])
    product_results = {}
    theme_rows = []
    distribution_rows = []
    low_rows = []
    opportunity_rows = []
    for product_name in products_config["products"]:
        selected = [item for item in fetch_data["competitors"] if product_name in item["products"]]
        reviews_by_id = {}
        for competitor in selected:
            for review in competitor["sampled_reviews"]:
                enriched = dict(review)
                enriched["track_name"] = competitor["metadata"].get("trackName", "")
                reviews_by_id.setdefault(review["review_id"], enriched)
        reviews = sorted(reviews_by_id.values(), key=lambda item: (item.get("updated", ""), item["review_id"]), reverse=True)
        rated = [review for review in reviews if review.get("rating") in {1, 2, 3, 4, 5}]
        rated_count = len(rated)
        low = [review for review in rated if review["rating"] <= int(config["low_rating_threshold"])]
        theme_results = {}
        matched_pain_ids = set()
        for theme_key in config["product_themes"][product_name]:
            theme = config["themes"][theme_key]
            matches = []
            for review in rated:
                if review["rating"] > int(theme["ratings_maximum"]):
                    continue
                phrases = _theme_matches(review, theme)
                if phrases:
                    matches.append(
                        {
                            "review_id": review["review_id"],
                            "track_id": review["track_id"],
                            "track_name": review["track_name"],
                            "rating": review["rating"],
                            "updated": review.get("updated", ""),
                            "matched_phrases": phrases,
                        }
                    )
            unique_matches = {item["review_id"]: item for item in matches}
            matches = sorted(unique_matches.values(), key=lambda item: (item["updated"], item["review_id"]), reverse=True)
            is_pain = int(theme["ratings_maximum"]) <= int(config["pain_rating_maximum"])
            if is_pain:
                matched_pain_ids.update(unique_matches)
            share = len(matches) / rated_count if rated_count else None
            theme_results[theme_key] = {
                "label": theme["label"],
                "generated_inference": True,
                "rating_filter": "ratings <= {}".format(theme["ratings_maximum"]),
                "review_count": len(matches),
                "share_of_rated_sample": round_number(share),
                "review_ids": [item["review_id"] for item in matches[:maximum_ids]],
                "evidence": matches[:maximum_ids],
            }
            theme_rows.append(
                {
                    "product": product_name,
                    "theme": theme_key,
                    "label": theme["label"],
                    "rating_filter": theme_results[theme_key]["rating_filter"],
                    "review_count": len(matches),
                    "share_of_rated_sample": round_number(share),
                    "review_ids": [item["review_id"] for item in matches[:maximum_ids]],
                    "matched_phrases": sorted({phrase for item in matches for phrase in item["matched_phrases"]}),
                    "generated_inference": True,
                }
            )
        pricing_theme = config["themes"]["pricing_subscription"]
        pricing_ids = {
            review["review_id"]
            for review in rated
            if review["rating"] <= int(pricing_theme["ratings_maximum"]) and _theme_matches(review, pricing_theme)
        }
        largest_pain_count = max(
            [details["review_count"] for key, details in theme_results.items() if int(config["themes"][key]["ratings_maximum"]) <= int(config["pain_rating_maximum"])] or [0]
        )
        demand_count = sum(int((item["metadata"].get("userRatingCount") or 0)) for item in selected)
        score_config = config["opportunity_score"]
        ceiling = int(score_config["demand_rating_count_ceiling"])
        components = {
            "low_rating_share": len(low) / rated_count if rated_count else None,
            "pain_review_share": len(matched_pain_ids) / rated_count if rated_count else None,
            "largest_recurring_pain_theme_share": largest_pain_count / rated_count if rated_count else None,
            "pricing_complaint_share": len(pricing_ids) / rated_count if rated_count else None,
            "bounded_demand_signal": min(1.0, math.log1p(demand_count) / math.log1p(ceiling)) if demand_count >= 0 and ceiling > 1 else None,
        }
        minimum_sample = int(score_config["minimum_rated_reviews_for_score"])
        if rated_count >= minimum_sample and all(value is not None for value in components.values()):
            score = 100.0 * sum(float(score_config["weights"][key]) * value for key, value in components.items())
            score_status = "computed"
            score_reason = None
        else:
            score = None
            score_status = "insufficient_sample"
            score_reason = "At least {} rated sampled reviews are required; found {}.".format(minimum_sample, rated_count)
        opportunity = {
            "score": round_number(score, 2),
            "status": score_status,
            "reason": score_reason,
            "label": score_config["label"],
            "formula": score_config["formula"],
            "weights": score_config["weights"],
            "components": {key: round_number(value) for key, value in components.items()},
            "numerators_and_denominators": {
                "rated_sample_reviews": rated_count,
                "low_rating_reviews": len(low),
                "unique_pain_reviews": len(matched_pain_ids),
                "largest_pain_theme_review_count": largest_pain_count,
                "pricing_complaint_reviews": len(pricing_ids),
                "competitor_metadata_rating_count_sum": demand_count,
            },
            "limitations": score_config["limitations"],
        }
        low_records = []
        for review in low[:int(config["maximum_low_rating_records"])]:
            low_records.append(
                {
                    "review_id": review["review_id"],
                    "track_id": review["track_id"],
                    "track_name": review["track_name"],
                    "rating": review["rating"],
                    "updated": review.get("updated"),
                    "version": review.get("version"),
                    "title": review.get("title"),
                    "text": review.get("text"),
                    "review_url": review.get("review_url"),
                    "source_url": review.get("source_url"),
                    "fetched_at_utc": review.get("fetched_at_utc"),
                }
            )
        ngram_reviews = [review for review in rated if review["rating"] <= int(config["pain_rating_maximum"])]
        ngrams = _ngrams(ngram_reviews, config["ngrams"], maximum_ids)[:int(config["maximum_ngrams_per_product"])]
        competitor_results = []
        for competitor in sorted(selected, key=lambda item: int(item["track_id"])):
            metadata = competitor["metadata"]
            distribution = _rating_distribution(competitor["sampled_reviews"])
            competitor_results.append(
                {
                    "track_id": competitor["track_id"],
                    "track_name": metadata.get("trackName"),
                    "seller_name": metadata.get("sellerName"),
                    "app_store_metadata": {
                        "average_user_rating": metadata.get("averageUserRating"),
                        "user_rating_count": metadata.get("userRatingCount"),
                        "current_version_average_rating": metadata.get("averageUserRatingForCurrentVersion"),
                        "current_version_rating_count": metadata.get("userRatingCountForCurrentVersion"),
                        "formatted_price": metadata.get("formattedPrice"),
                        "version": metadata.get("version"),
                        "track_view_url": metadata.get("trackViewUrl"),
                    },
                    "recent_review_sample": distribution,
                    "lookup_source": competitor["lookup_source"],
                }
            )
            for rating in range(1, 6):
                distribution_rows.append(
                    {
                        "product": product_name,
                        "track_id": competitor["track_id"],
                        "track_name": metadata.get("trackName"),
                        "rating": rating,
                        "sample_count": distribution["counts"][str(rating)],
                        "sample_share": distribution["shares"][str(rating)],
                        "sampled_rated_review_count": distribution["sampled_rated_review_count"],
                        "app_store_average_rating": metadata.get("averageUserRating"),
                        "app_store_user_rating_count": metadata.get("userRatingCount"),
                        "scope": "recent RSS sample; not full App Store rating histogram",
                    }
                )
        for record in low_records:
            low_rows.append({"product": product_name, **record})
        product_results[product_name] = {
            "competitors": competitor_results,
            "sample_scope": fetch_data["review_sample_scope"],
            "rating_distribution": _rating_distribution(reviews),
            "recent_low_rating_reviews": low_records,
            "themes": theme_results,
            "pricing_subscription_complaints": theme_results["pricing_subscription"],
            "keyword_ngrams": {
                "scope": "Reviews rated 1-3; counts are unique reviews containing the n-gram after configured stop-word removal.",
                "items": ngrams,
            },
            "opportunity": opportunity,
        }
        opportunity_rows.append(
            {
                "product": product_name,
                "opportunity_score": round_number(score, 2),
                "status": score_status,
                "rated_sample_reviews": rated_count,
                "low_rating_reviews": len(low),
                "unique_pain_reviews": len(matched_pain_ids),
                "largest_pain_theme_review_count": largest_pain_count,
                "pricing_complaint_reviews": len(pricing_ids),
                "competitor_metadata_rating_count_sum": demand_count,
                "low_rating_share": round_number(components["low_rating_share"]),
                "pain_review_share": round_number(components["pain_review_share"]),
                "largest_recurring_pain_theme_share": round_number(components["largest_recurring_pain_theme_share"]),
                "pricing_complaint_share": round_number(components["pricing_complaint_share"]),
                "bounded_demand_signal": round_number(components["bounded_demand_signal"]),
                "formula": score_config["formula"],
                "generated_inference": True,
            }
        )
    payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "generated_output_label": config["generated_output_label"],
        "input_provenance": {
            "path": str(input_path) if input_path else None,
            "fetched_at_utc": fetch_data.get("generated_at_utc"),
            "country": fetch_data.get("country"),
        },
        "method": {
            "theme_matching": "Case-folded local phrase matching against review title and text. Short phrases use token boundaries; longer phrases allow substring forms. A review can match multiple themes.",
            "ngrams": "Configured 1-3 token n-grams, stop-word removal, and unique-review counting over reviews rated 1-3.",
            "opportunity_score": config["opportunity_score"],
        },
        "products": product_results,
        "fetch_errors": fetch_data.get("errors", []),
    }
    output_dir = Path(output_dir)
    write_json(output_dir / "analysis.json", payload)
    write_csv(
        output_dir / "themes.csv",
        ["product", "theme", "label", "rating_filter", "review_count", "share_of_rated_sample", "review_ids", "matched_phrases", "generated_inference"],
        sorted(theme_rows, key=lambda row: (row["product"], -row["review_count"], row["theme"])),
    )
    write_csv(
        output_dir / "rating_distribution.csv",
        ["product", "track_id", "track_name", "rating", "sample_count", "sample_share", "sampled_rated_review_count", "app_store_average_rating", "app_store_user_rating_count", "scope"],
        sorted(distribution_rows, key=lambda row: (row["product"], row["track_id"], row["rating"])),
    )
    write_csv(
        output_dir / "low_rating_reviews.csv",
        ["product", "review_id", "track_id", "track_name", "rating", "updated", "version", "title", "text", "review_url", "source_url", "fetched_at_utc"],
        sorted(low_rows, key=lambda row: (row["product"], row["updated"] or "", row["review_id"]), reverse=True),
    )
    write_csv(
        output_dir / "opportunities.csv",
        ["product", "opportunity_score", "status", "rated_sample_reviews", "low_rating_reviews", "unique_pain_reviews", "largest_pain_theme_review_count", "pricing_complaint_reviews", "competitor_metadata_rating_count_sum", "low_rating_share", "pain_review_share", "largest_recurring_pain_theme_share", "pricing_complaint_share", "bounded_demand_signal", "formula", "generated_inference"],
        sorted(opportunity_rows, key=lambda row: row["product"]),
    )
    write_csv(
        output_dir / "keyword_ngrams.csv",
        ["product", "ngram", "review_count", "review_ids", "scope"],
        [
            {"product": product, "ngram": item["ngram"], "review_count": item["review_count"], "review_ids": item["review_ids"], "scope": details["keyword_ngrams"]["scope"]}
            for product, details in product_results.items()
            for item in details["keyword_ngrams"]["items"]
        ],
    )
    return payload
