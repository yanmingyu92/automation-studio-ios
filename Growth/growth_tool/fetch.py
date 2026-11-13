import hashlib
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

from .common import GENERATED_LABEL, utc_now, write_csv, write_json


class FetchFailure(Exception):
    pass


class PublicFetcher:
    def __init__(self, cache_dir, settings, offline=False, refresh=False):
        self.cache_dir = Path(cache_dir)
        self.settings = settings
        self.offline = offline
        self.refresh = refresh
        self.last_request_by_host = {}

    def get_json(self, url):
        key = hashlib.sha256(url.encode("utf-8")).hexdigest()
        path = self.cache_dir / (key + ".json")
        cached = self._read_cache(path)
        if cached and not self.refresh:
            return cached["body"], self._provenance(url, cached["fetched_at"], True)
        if self.offline:
            raise FetchFailure("No fresh cached response in offline mode: " + url)
        self._throttle(url)
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/json",
                "User-Agent": self.settings["user_agent"],
            },
            method="GET",
        )
        attempts = int(self.settings["retries"]) + 1
        for attempt in range(attempts):
            try:
                with urllib.request.urlopen(request, timeout=float(self.settings["timeout_seconds"])) as response:
                    raw = response.read()
                    charset = response.headers.get_content_charset() or "utf-8"
                body = json.loads(raw.decode(charset))
                fetched_at = utc_now()
                write_json(path, {"request_url": url, "fetched_at": fetched_at, "body": body})
                return body, self._provenance(url, fetched_at, False)
            except urllib.error.HTTPError as error:
                retryable = error.code == 429 or 500 <= error.code <= 599
                if not retryable or attempt == attempts - 1:
                    raise FetchFailure("HTTP {} for {}".format(error.code, url)) from error
                retry_after = error.headers.get("Retry-After") if error.headers else None
                self._sleep_before_retry(attempt, retry_after)
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError) as error:
                if attempt == attempts - 1:
                    raise FetchFailure("Request or JSON decoding failed for {}: {}".format(url, error)) from error
                self._sleep_before_retry(attempt, None)
        raise FetchFailure("Request failed: " + url)

    def _read_cache(self, path):
        try:
            if time.time() - path.stat().st_mtime > float(self.settings["cache_ttl_seconds"]):
                return None
            with path.open("r", encoding="utf-8") as handle:
                value = json.load(handle)
            if value.get("request_url") and "body" in value and value.get("fetched_at"):
                return value
        except (OSError, ValueError, TypeError):
            return None
        return None

    def _provenance(self, url, fetched_at, cache_hit):
        return {"source_url": url, "fetched_at_utc": fetched_at, "cache_hit": cache_hit}

    def _throttle(self, url):
        host = urllib.parse.urlparse(url).netloc
        minimum = float(self.settings["minimum_request_interval_seconds"])
        elapsed = time.monotonic() - self.last_request_by_host.get(host, 0.0)
        if host in self.last_request_by_host and elapsed < minimum:
            time.sleep(minimum - elapsed)
        self.last_request_by_host[host] = time.monotonic()

    def _sleep_before_retry(self, attempt, retry_after):
        delay = float(self.settings["backoff_seconds"]) * (2 ** attempt)
        if retry_after:
            try:
                delay = max(delay, min(float(retry_after), 60.0))
            except ValueError:
                pass
        time.sleep(delay)


def _lookup_url(config, track_id):
    return config["lookup_url"].format(track_id=urllib.parse.quote(str(track_id)))


def _search_url(config, term):
    query = urllib.parse.urlencode(
        {
            "term": term,
            "country": config["country"],
            "media": "software",
            "entity": "software",
            "limit": int(config["search"]["limit"]),
        }
    )
    return config["search_url"].format(query=query)


def _review_url(config, track_id, page):
    return config["review_feed"]["url_template"].format(track_id=track_id, page=page)


def discover(config, products_config, output_dir, fetcher):
    generated_at = utc_now()
    candidates = {}
    errors = []
    known = {
        str(track_id)
        for product in config["products"].values()
        for track_id in product["known_track_ids"]
    }
    for product_name, product in config["products"].items():
        for query in product["queries"]:
            url = _search_url(config, query["term"])
            try:
                body, source = fetcher.get_json(url)
            except FetchFailure as error:
                errors.append({"operation": "search", "product": product_name, "query": query["term"], "error": str(error)})
                continue
            for result in body.get("results", []):
                track_id = str(result.get("trackId", ""))
                if not track_id:
                    continue
                candidate = candidates.setdefault(
                    track_id,
                    {
                        "track_id": track_id,
                        "track_name": result.get("trackName", ""),
                        "seller_name": result.get("sellerName", ""),
                        "track_view_url": result.get("trackViewUrl", ""),
                        "genres": result.get("genres", []),
                        "queries": [],
                        "products": {},
                        "is_known_competitor": track_id in known,
                    },
                )
                if query["term"] not in candidate["queries"]:
                    candidate["queries"].append(query["term"])
                details = candidate["products"].setdefault(
                    product_name,
                    {"matched_queries": [], "matched_keywords": [], "relevance_score": 0},
                )
                if query["term"] not in details["matched_queries"]:
                    details["matched_queries"].append(query["term"])
                details["relevance_score"] += int(config["search"]["scoring"]["query_occurrence_points"])
                haystack_title = (result.get("trackName") or "").casefold()
                haystack_description = (result.get("description") or "").casefold()
                title_points = int(config["search"]["scoring"]["title_keyword_points"])
                description_points = int(config["search"]["scoring"]["description_keyword_points"])
                maximum_description = int(config["search"]["scoring"]["maximum_description_points"])
                description_score = 0
                for keyword in query["keywords"]:
                    folded = keyword.casefold()
                    matched_title = folded in haystack_title
                    matched_description = folded in haystack_description
                    if matched_title:
                        details["relevance_score"] += title_points
                    if matched_description:
                        description_score += description_points
                    if (matched_title or matched_description) and keyword not in details["matched_keywords"]:
                        details["matched_keywords"].append(keyword)
                details["relevance_score"] += min(description_score, maximum_description)
    minimum = int(config["search"]["minimum_relevance_score"])
    additional_limit = int(config["search"]["additional_per_product"])
    selected_by_product = {}
    for product_name in config["products"]:
        eligible = []
        for candidate in candidates.values():
            if product_name not in candidate["products"]:
                continue
            details = candidate["products"][product_name]
            if not candidate["is_known_competitor"] and details["relevance_score"] >= minimum:
                eligible.append(candidate)
        eligible.sort(key=lambda item: (-item["products"][product_name]["relevance_score"], item["track_name"].casefold(), item["track_id"]))
        seller_counts = defaultdict(int)
        selected_ids = []
        maximum_per_seller = int(config["search"].get("maximum_per_seller_per_product", 1))
        for candidate in eligible:
            seller_key = (candidate["seller_name"] or candidate["track_id"]).casefold()
            if seller_counts[seller_key] >= maximum_per_seller:
                continue
            selected_ids.append(candidate["track_id"])
            seller_counts[seller_key] += 1
            if len(selected_ids) == additional_limit:
                break
        selected_by_product[product_name] = selected_ids
    candidate_rows = []
    for track_id in sorted(candidates, key=lambda value: int(value) if value.isdigit() else value):
        candidate = candidates[track_id]
        candidate["selected_for"] = [name for name, ids in selected_by_product.items() if track_id in ids]
        candidate["selection_status"] = "known" if candidate["is_known_competitor"] else ("selected" if candidate["selected_for"] else "not_selected")
        candidate["generated_at_utc"] = generated_at
        candidate["source_urls"] = [_search_url(config, term) for term in candidate["queries"]]
        candidate_rows.append(candidate)
    payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "generated_output_label": GENERATED_LABEL,
        "selection_method": "Deterministic configured keyword scoring of iTunes Search results; selected candidates require manual relevance review before business decisions.",
        "selected_by_product": selected_by_product,
        "candidates": candidate_rows,
        "errors": errors,
    }
    write_json(Path(output_dir) / "discovered_candidates.json", payload)
    rows = []
    for candidate in candidate_rows:
        for product_name, details in sorted(candidate["products"].items()):
            rows.append(
                {
                    "track_id": candidate["track_id"],
                    "track_name": candidate["track_name"],
                    "seller_name": candidate["seller_name"],
                    "product": product_name,
                    "relevance_score": details["relevance_score"],
                    "matched_keywords": sorted(details["matched_keywords"]),
                    "matched_queries": details["matched_queries"],
                    "selection_status": candidate["selection_status"],
                    "selected_for_product": product_name in candidate["selected_for"],
                    "track_view_url": candidate["track_view_url"],
                }
            )
    write_csv(
        Path(output_dir) / "discovered_candidates.csv",
        ["track_id", "track_name", "seller_name", "product", "relevance_score", "matched_keywords", "matched_queries", "selection_status", "selected_for_product", "track_view_url"],
        sorted(rows, key=lambda row: (row["product"], -row["relevance_score"], row["track_name"].casefold(), row["track_id"])),
    )
    return payload


def _as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def _label(value, default=""):
    if isinstance(value, dict):
        return value.get("label", default)
    return value if value is not None else default


def _parse_reviews(feed, track_id, page, source):
    entries = _as_list((feed.get("feed") or {}).get("entry"))
    reviews = []
    for entry in entries:
        rating = _label(entry.get("im:rating"))
        if rating == "":
            continue
        content_values = _as_list(entry.get("content"))
        content = _label(content_values[0]) if content_values else ""
        author = (entry.get("author") or {}).get("name", {})
        review_id = str(_label(entry.get("id")))
        if not review_id:
            review_id = hashlib.sha256((str(_label(author)) + _label(entry.get("updated")) + content).encode("utf-8")).hexdigest()[:24]
        link = entry.get("link") or {}
        if isinstance(link, list):
            link = link[0] if link else {}
        review_url = (link.get("attributes") or {}).get("href", "") if isinstance(link, dict) else ""
        try:
            parsed_rating = int(rating)
        except (TypeError, ValueError):
            continue
        reviews.append(
            {
                "review_id": review_id,
                "track_id": str(track_id),
                "rating": parsed_rating,
                "title": _label(entry.get("title")),
                "text": content,
                "author_name": _label(author),
                "version": _label(entry.get("im:version")),
                "updated": _label(entry.get("updated")),
                "vote_sum": int(_label(entry.get("im:voteSum"), "0") or 0),
                "vote_count": int(_label(entry.get("im:voteCount"), "0") or 0),
                "review_url": review_url,
                "source_url": source["source_url"],
                "fetched_at_utc": source["fetched_at_utc"],
                "feed_page": page,
            }
        )
    return reviews


def fetch_competitors(config, discovery, output_dir, fetcher, pages=None):
    page_count = pages if pages is not None else int(config["review_feed"]["pages"])
    page_count = max(1, min(page_count, int(config["review_feed"]["maximum_supported_pages"])))
    selected = {}
    for product_name, product in config["products"].items():
        for track_id in product["known_track_ids"] + discovery.get("selected_by_product", {}).get(product_name, []):
            membership = selected.setdefault(str(track_id), {"products": [], "known": False})
            membership["known"] = membership["known"] or str(track_id) in product["known_track_ids"]
            if product_name not in membership["products"]:
                membership["products"].append(product_name)
    candidate_names = {item["track_id"]: item["track_name"] for item in discovery.get("candidates", [])}
    competitors = []
    errors = list(discovery.get("errors", []))
    all_reviews = []
    for track_id in sorted(selected, key=lambda value: int(value) if value.isdigit() else value):
        membership = selected[track_id]
        lookup_url = _lookup_url(config, track_id)
        metadata = {}
        lookup_source = {"source_url": lookup_url, "fetched_at_utc": None, "cache_hit": None}
        try:
            body, lookup_source = fetcher.get_json(lookup_url)
            results = body.get("results", [])
            if not results:
                raise FetchFailure("iTunes Lookup returned no software result for " + track_id)
            metadata = results[0]
        except FetchFailure as error:
            errors.append({"operation": "lookup", "track_id": track_id, "error": str(error)})
        review_sources = []
        deduplicated = {}
        for page in range(1, page_count + 1):
            url = _review_url(config, track_id, page)
            try:
                feed, source = fetcher.get_json(url)
            except FetchFailure as error:
                errors.append({"operation": "reviews", "track_id": track_id, "page": page, "error": str(error)})
                continue
            review_sources.append(source)
            page_reviews = _parse_reviews(feed, track_id, page, source)
            for review in page_reviews:
                deduplicated.setdefault(review["review_id"], review)
            if not page_reviews:
                break
        reviews = sorted(deduplicated.values(), key=lambda item: (item["updated"], item["review_id"]), reverse=True)
        for review in reviews:
            review["products"] = sorted(membership["products"])
            review["track_name"] = metadata.get("trackName") or candidate_names.get(track_id, "")
        all_reviews.extend(reviews)
        public_metadata = {
            key: metadata.get(key)
            for key in (
                "trackId", "trackName", "sellerName", "artistName", "bundleId", "primaryGenreName", "genres",
                "averageUserRating", "userRatingCount", "averageUserRatingForCurrentVersion", "userRatingCountForCurrentVersion",
                "version", "currentVersionReleaseDate", "releaseDate", "minimumOsVersion", "formattedPrice", "price",
                "currency", "trackViewUrl", "description", "languageCodesISO2A", "fileSizeBytes"
            )
            if key in metadata
        }
        competitors.append(
            {
                "track_id": track_id,
                "products": sorted(membership["products"]),
                "known_competitor": membership["known"],
                "metadata": public_metadata,
                "lookup_source": lookup_source,
                "review_sources": review_sources,
                "sampled_reviews": reviews,
                "sampled_review_count": len(reviews),
            }
        )
    generated_at = utc_now()
    payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "generated_output_label": GENERATED_LABEL,
        "country": config["country"],
        "review_sample_scope": "Most recent public Apple RSS reviews, up to {} pages per competitor; deduplicated by review ID. Not a complete or random sample.".format(page_count),
        "competitors": competitors,
        "errors": errors,
    }
    output_dir = Path(output_dir)
    write_json(output_dir / "competitors.json", payload)
    write_csv(output_dir / "competitors.csv", *competitor_csv_rows(competitors))
    write_csv(output_dir / "reviews.csv", *review_csv_rows(all_reviews))
    write_json(
        output_dir / "fetch_report.json",
        {
            "generated_at_utc": generated_at,
            "competitor_count": len(competitors),
            "review_count": len(all_reviews),
            "error_count": len(errors),
            "errors": errors,
            "cache_directory": str(fetcher.cache_dir),
        },
    )
    return payload


def competitor_csv_rows(competitors):
    rows = []
    for competitor in competitors:
        metadata = competitor["metadata"]
        rows.append(
            {
                "track_id": competitor["track_id"],
                "products": competitor["products"],
                "known_competitor": competitor["known_competitor"],
                "track_name": metadata.get("trackName"),
                "seller_name": metadata.get("sellerName"),
                "primary_genre": metadata.get("primaryGenreName"),
                "average_user_rating": metadata.get("averageUserRating"),
                "user_rating_count": metadata.get("userRatingCount"),
                "current_version_average_rating": metadata.get("averageUserRatingForCurrentVersion"),
                "current_version_rating_count": metadata.get("userRatingCountForCurrentVersion"),
                "version": metadata.get("version"),
                "formatted_price": metadata.get("formattedPrice"),
                "track_view_url": metadata.get("trackViewUrl"),
                "sampled_review_count": competitor["sampled_review_count"],
                "lookup_source_url": competitor["lookup_source"]["source_url"],
                "fetched_at_utc": competitor["lookup_source"]["fetched_at_utc"],
            }
        )
    return ["track_id", "products", "known_competitor", "track_name", "seller_name", "primary_genre", "average_user_rating", "user_rating_count", "current_version_average_rating", "current_version_rating_count", "version", "formatted_price", "track_view_url", "sampled_review_count", "lookup_source_url", "fetched_at_utc"], sorted(rows, key=lambda row: (row["products"], int(row["track_id"])))


def review_csv_rows(reviews):
    fields = ["products", "track_id", "track_name", "review_id", "rating", "updated", "version", "title", "text", "author_name", "vote_sum", "vote_count", "review_url", "source_url", "fetched_at_utc", "feed_page"]
    return fields, sorted(reviews, key=lambda item: (item["products"], item["track_id"], item["updated"], item["review_id"]), reverse=True)
