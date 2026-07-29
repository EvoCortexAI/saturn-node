#!/usr/bin/env python3
"""Validate Saturn-Node v1 contract fixtures with Python standard library only."""

from __future__ import annotations

import copy
import json
import re
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DIR = ROOT / "docs" / "contracts" / "v1"
SCHEMA_PATH = CONTRACT_DIR / "schema.json"
FIXTURES_PATH = CONTRACT_DIR / "fixtures.json"
STREAM_PATH = CONTRACT_DIR / "stream.sse"

CONTRACT_VERSION = "1"
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")
NONCE_RE = re.compile(r"^[A-Za-z0-9_-]+$")

PROBLEM_CODES = {
    "contract_version_unsupported",
    "malformed_request",
    "unauthenticated",
    "unauthorized",
    "wrong_audience",
    "wrong_workload",
    "wrong_deployment",
    "wrong_node",
    "model_not_allowed",
    "credential_not_yet_valid",
    "credential_expired",
    "credential_revoked",
    "credential_replayed",
    "stale_credential_epoch",
    "request_limit_exceeded",
    "token_budget_exceeded",
    "node_saturated",
    "request_timeout",
    "cancelled",
    "internal_failure",
}

CLAIMS_REQUIRED = {
    "contractVersion",
    "credentialId",
    "issuer",
    "audience",
    "workloadId",
    "deploymentId",
    "nodeId",
    "modelId",
    "maximumContextTokens",
    "maximumOutputTokens",
    "maximumConcurrentRequests",
    "requestBudget",
    "tokenBudget",
    "issuedAt",
    "notBefore",
    "expiresAt",
    "epoch",
}
CLAIMS_OPTIONAL = {"policyReference", "approvalReference"}

REQUEST_REQUIRED = {
    "contractVersion",
    "requestId",
    "requestNonce",
    "workloadId",
    "deploymentId",
    "modelId",
    "inputText",
    "maximumContextTokens",
    "maximumOutputTokens",
    "deadlineAt",
}

CAPABILITIES_REQUIRED = {
    "contractVersion",
    "nodeId",
    "serviceVersion",
    "state",
    "models",
    "maximumConcurrentRequests",
    "acceptedCredentialEpoch",
}

USAGE_REQUIRED = {
    "contractVersion",
    "requestId",
    "workloadId",
    "deploymentId",
    "nodeId",
    "modelId",
    "startedAt",
    "completedAt",
    "inputTokens",
    "outputTokens",
    "outcome",
}
USAGE_OPTIONAL = {"policyReference", "approvalReference"}

CANCELLATION_REQUIRED = {"contractVersion", "requestId", "state"}
PROBLEM_REQUIRED = {"type", "title", "status", "code", "requestId"}
PROBLEM_OPTIONAL = {"detail", "retryAfterSeconds"}


class ContractError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class ParsedSSEEvent:
    event: str
    event_id: str | None
    data: str


class IncrementalSSEParser:
    def __init__(self) -> None:
        self.buffer = ""
        self.event_name: str | None = None
        self.event_id: str | None = None
        self.data_lines: list[str] = []
        self.events: list[ParsedSSEEvent] = []

    def feed(self, chunk: str, *, final: bool = False) -> None:
        self.buffer += chunk
        while "\n" in self.buffer:
            line, self.buffer = self.buffer.split("\n", 1)
            self._process_line(line.rstrip("\r"))

        if final:
            if self.buffer:
                self._process_line(self.buffer.rstrip("\r"))
                self.buffer = ""
            self._process_line("")

    def _process_line(self, line: str) -> None:
        if line == "":
            if self.event_name is not None or self.event_id is not None or self.data_lines:
                self.events.append(
                    ParsedSSEEvent(
                        event=self.event_name or "message",
                        event_id=self.event_id,
                        data="\n".join(self.data_lines),
                    )
                )
            self.event_name = None
            self.event_id = None
            self.data_lines = []
            return

        if line.startswith(":"):
            return

        field, separator, value = line.partition(":")
        if not separator:
            value = ""
        elif value.startswith(" "):
            value = value[1:]

        if field == "event":
            self.event_name = value
        elif field == "id":
            self.event_id = value
        elif field == "data":
            self.data_lines.append(value)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError("malformed_request", f"Cannot load {path}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError("malformed_request", f"{path} must contain a JSON object")
    return value


def require_exact_fields(
    value: dict[str, Any],
    required: set[str],
    optional: set[str] | None = None,
    *,
    code: str = "malformed_request",
) -> None:
    optional = optional or set()
    keys = set(value)
    missing = required - keys
    unknown = keys - required - optional
    if missing:
        raise ContractError(code, f"Missing required fields: {sorted(missing)}")
    if unknown:
        raise ContractError(code, f"Unknown fields: {sorted(unknown)}")


def require_contract_version(value: Any) -> None:
    if value != CONTRACT_VERSION:
        raise ContractError(
            "contract_version_unsupported",
            f"Unsupported contract version: {value!r}",
        )


def require_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 128 or not IDENTIFIER_RE.fullmatch(value):
        raise ContractError("malformed_request", f"Invalid identifier in {field}")
    return value


def require_uuid(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise ContractError("malformed_request", f"{field} must be a UUID string")
    try:
        parsed = uuid.UUID(value)
    except ValueError as error:
        raise ContractError("malformed_request", f"{field} must be a UUID") from error
    if str(parsed) != value.lower():
        raise ContractError("malformed_request", f"{field} must use canonical UUID form")
    return value


def require_positive_int(value: Any, field: str, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ContractError("request_limit_exceeded", f"{field} must be a positive integer")
    if maximum is not None and value > maximum:
        raise ContractError("request_limit_exceeded", f"{field} exceeds its contract maximum")
    return value


def require_non_negative_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ContractError("malformed_request", f"{field} must be a non-negative integer")
    return value


def parse_timestamp(value: Any, field: str) -> datetime:
    if not isinstance(value, str):
        raise ContractError("malformed_request", f"{field} must be an ISO-8601 string")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise ContractError("malformed_request", f"Invalid timestamp in {field}") from error
    if parsed.tzinfo is None:
        raise ContractError("malformed_request", f"{field} must include a timezone")
    return parsed.astimezone(timezone.utc)


def validate_request(value: dict[str, Any], now: datetime) -> None:
    require_exact_fields(value, REQUEST_REQUIRED)
    require_contract_version(value["contractVersion"])
    require_uuid(value["requestId"], "requestId")

    nonce = value["requestNonce"]
    if not isinstance(nonce, str) or not 16 <= len(nonce) <= 128 or not NONCE_RE.fullmatch(nonce):
        raise ContractError("malformed_request", "requestNonce is invalid")

    require_identifier(value["workloadId"], "workloadId")
    require_identifier(value["deploymentId"], "deploymentId")
    require_identifier(value["modelId"], "modelId")

    input_text = value["inputText"]
    if not isinstance(input_text, str) or not input_text or len(input_text) > 1_000_000:
        raise ContractError("malformed_request", "inputText must be non-empty and bounded")

    maximum_context = require_positive_int(
        value["maximumContextTokens"], "maximumContextTokens", 1_048_576
    )
    maximum_output = require_positive_int(
        value["maximumOutputTokens"], "maximumOutputTokens", 65_536
    )
    if maximum_output > maximum_context:
        raise ContractError("request_limit_exceeded", "Output limit exceeds context limit")

    deadline = parse_timestamp(value["deadlineAt"], "deadlineAt")
    if deadline <= now:
        raise ContractError("request_timeout", "Request deadline has already elapsed")


def validate_claims(
    value: dict[str, Any],
    request: dict[str, Any],
    context: dict[str, Any],
    now: datetime,
) -> None:
    require_exact_fields(value, CLAIMS_REQUIRED, CLAIMS_OPTIONAL, code="unauthorized")
    require_contract_version(value["contractVersion"])

    require_identifier(value["credentialId"], "credentialId")
    if value["issuer"] != "saturn-control":
        raise ContractError("unauthenticated", "Credential issuer is not trusted")

    node_id = require_identifier(value["nodeId"], "nodeId")
    audience = value["audience"]
    if audience != f"saturn-node:{node_id}":
        raise ContractError("wrong_audience", "Credential audience does not match its node binding")

    workload_id = require_identifier(value["workloadId"], "workloadId")
    deployment_id = require_identifier(value["deploymentId"], "deploymentId")
    model_id = require_identifier(value["modelId"], "modelId")

    maximum_context = require_positive_int(
        value["maximumContextTokens"], "maximumContextTokens", 1_048_576
    )
    maximum_output = require_positive_int(
        value["maximumOutputTokens"], "maximumOutputTokens", 65_536
    )
    if maximum_output > maximum_context:
        raise ContractError("request_limit_exceeded", "Credential output limit exceeds context limit")

    require_positive_int(value["maximumConcurrentRequests"], "maximumConcurrentRequests", 1_024)
    request_budget = require_positive_int(value["requestBudget"], "requestBudget", 1_000_000)
    token_budget = require_positive_int(value["tokenBudget"], "tokenBudget", 1_000_000_000)

    issued_at = parse_timestamp(value["issuedAt"], "issuedAt")
    not_before = parse_timestamp(value["notBefore"], "notBefore")
    expires_at = parse_timestamp(value["expiresAt"], "expiresAt")
    if not issued_at <= not_before < expires_at:
        raise ContractError("unauthorized", "Credential time ordering is invalid")

    epoch = require_non_negative_int(value["epoch"], "epoch")
    skew = timedelta(seconds=max(0, int(context["clockSkewAllowanceSeconds"])))

    if now + skew < not_before:
        raise ContractError("credential_not_yet_valid", "Credential is not yet valid")
    if now - skew >= expires_at:
        raise ContractError("credential_expired", "Credential has expired")

    expected_node = context["nodeId"]
    expected_workload = context["workloadId"]
    expected_deployment = context["deploymentId"]
    expected_model = context["modelId"]
    expected_epoch = context["acceptedEpoch"]

    if node_id != expected_node:
        raise ContractError("wrong_node", "Credential is bound to a different node")
    if workload_id != expected_workload or request["workloadId"] != expected_workload:
        raise ContractError("wrong_workload", "Workload binding does not match")
    if deployment_id != expected_deployment or request["deploymentId"] != expected_deployment:
        raise ContractError("wrong_deployment", "Deployment binding does not match")
    if model_id != expected_model or request["modelId"] != expected_model:
        raise ContractError("model_not_allowed", "Model binding does not match")
    if epoch != expected_epoch:
        raise ContractError("stale_credential_epoch", "Credential epoch is stale")

    if request["maximumContextTokens"] > maximum_context or request["maximumOutputTokens"] > maximum_output:
        raise ContractError("request_limit_exceeded", "Request exceeds credential limits")
    if request_budget < 1:
        raise ContractError("request_limit_exceeded", "Request budget is exhausted")
    if token_budget < request["maximumContextTokens"] + request["maximumOutputTokens"]:
        raise ContractError("token_budget_exceeded", "Token budget cannot cover the bounded request")

    if request["requestId"] in set(context.get("seenRequestIds", [])):
        raise ContractError("credential_replayed", "Request ID was already used")
    if request["requestNonce"] in set(context.get("seenRequestNonces", [])):
        raise ContractError("credential_replayed", "Request nonce was already used")


def validate_capabilities(value: dict[str, Any]) -> None:
    require_exact_fields(value, CAPABILITIES_REQUIRED)
    require_contract_version(value["contractVersion"])
    require_identifier(value["nodeId"], "nodeId")
    if not isinstance(value["serviceVersion"], str) or not 1 <= len(value["serviceVersion"]) <= 64:
        raise ContractError("malformed_request", "serviceVersion is invalid")
    if value["state"] not in {"available", "degraded", "saturated", "unavailable"}:
        raise ContractError("malformed_request", "Unknown runtime state")

    models = value["models"]
    if not isinstance(models, list) or not 1 <= len(models) <= 64:
        raise ContractError("malformed_request", "models must be a non-empty bounded array")
    seen: set[str] = set()
    for model in models:
        if not isinstance(model, dict):
            raise ContractError("malformed_request", "model capability must be an object")
        require_exact_fields(
            model,
            {"modelId", "maximumContextTokens", "maximumOutputTokens"},
        )
        model_id = require_identifier(model["modelId"], "modelId")
        if model_id in seen:
            raise ContractError("malformed_request", "Duplicate model capability")
        seen.add(model_id)
        maximum_context = require_positive_int(
            model["maximumContextTokens"], "maximumContextTokens", 1_048_576
        )
        maximum_output = require_positive_int(
            model["maximumOutputTokens"], "maximumOutputTokens", 65_536
        )
        if maximum_output > maximum_context:
            raise ContractError("request_limit_exceeded", "Model output limit exceeds context limit")

    require_positive_int(value["maximumConcurrentRequests"], "maximumConcurrentRequests", 1_024)
    require_non_negative_int(value["acceptedCredentialEpoch"], "acceptedCredentialEpoch")


def validate_usage(value: dict[str, Any]) -> None:
    require_exact_fields(value, USAGE_REQUIRED, USAGE_OPTIONAL)
    require_contract_version(value["contractVersion"])
    require_uuid(value["requestId"], "requestId")
    for field in ("workloadId", "deploymentId", "nodeId", "modelId"):
        require_identifier(value[field], field)
    started_at = parse_timestamp(value["startedAt"], "startedAt")
    completed_at = parse_timestamp(value["completedAt"], "completedAt")
    if completed_at < started_at:
        raise ContractError("malformed_request", "Usage completion precedes start")
    require_non_negative_int(value["inputTokens"], "inputTokens")
    require_non_negative_int(value["outputTokens"], "outputTokens")
    if value["outcome"] not in {"completed", "cancelled", "failed"}:
        raise ContractError("malformed_request", "Unknown usage outcome")
    forbidden = {"inputText", "prompt", "generatedText", "authorization", "credential"}
    if forbidden.intersection(value):
        raise ContractError("malformed_request", "Usage evidence contains forbidden content")


def validate_cancellation(value: dict[str, Any]) -> None:
    require_exact_fields(value, CANCELLATION_REQUIRED)
    require_contract_version(value["contractVersion"])
    require_uuid(value["requestId"], "requestId")
    if value["state"] not in {"cancellation_requested", "cancelled"}:
        raise ContractError("malformed_request", "Unknown cancellation state")


def validate_problem(value: dict[str, Any]) -> None:
    require_exact_fields(value, PROBLEM_REQUIRED, PROBLEM_OPTIONAL)
    if not isinstance(value["type"], str) or not value["type"]:
        raise ContractError("malformed_request", "Problem type is invalid")
    if not isinstance(value["title"], str) or not 1 <= len(value["title"]) <= 256:
        raise ContractError("malformed_request", "Problem title is invalid")
    status = value["status"]
    if isinstance(status, bool) or not isinstance(status, int) or not 400 <= status <= 599:
        raise ContractError("malformed_request", "Problem status is invalid")
    if value["code"] not in PROBLEM_CODES:
        raise ContractError("malformed_request", "Unknown problem code")
    require_uuid(value["requestId"], "requestId")
    if "retryAfterSeconds" in value:
        retry = value["retryAfterSeconds"]
        if isinstance(retry, bool) or not isinstance(retry, int) or not 0 <= retry <= 3600:
            raise ContractError("malformed_request", "Retry hint is invalid")


def validate_stream_event(payload: dict[str, Any], expected_sequence: int) -> str:
    common = {"contractVersion", "requestId", "sequence", "type"}
    event_type = payload.get("type")
    required_by_type = {
        "started": {"nodeId", "modelId"},
        "delta": {"delta"},
        "usage": {"inputTokens", "outputTokens"},
        "completed": {"finishReason"},
        "cancelled": {"finishReason"},
    }
    if event_type not in required_by_type:
        raise ContractError("malformed_request", f"Unknown stream event type: {event_type!r}")
    allowed = common | required_by_type[event_type]
    require_exact_fields(payload, common | required_by_type[event_type])
    require_contract_version(payload["contractVersion"])
    require_uuid(payload["requestId"], "requestId")
    if payload["sequence"] != expected_sequence:
        raise ContractError("malformed_request", "Stream sequence is not contiguous")

    if event_type == "started":
        require_identifier(payload["nodeId"], "nodeId")
        require_identifier(payload["modelId"], "modelId")
    elif event_type == "delta":
        if not isinstance(payload["delta"], str) or not payload["delta"] or len(payload["delta"]) > 65_536:
            raise ContractError("malformed_request", "Delta is empty or unbounded")
    elif event_type == "usage":
        require_non_negative_int(payload["inputTokens"], "inputTokens")
        require_non_negative_int(payload["outputTokens"], "outputTokens")
    elif event_type == "completed":
        if payload["finishReason"] not in {"stop", "length"}:
            raise ContractError("malformed_request", "Completed event has an invalid finish reason")
    elif event_type == "cancelled":
        if payload["finishReason"] != "cancelled":
            raise ContractError("malformed_request", "Cancelled event has an invalid finish reason")

    if set(payload) != allowed:
        raise ContractError("malformed_request", "Stream event contains fields outside its event shape")
    return event_type


def parse_fragmented_stream(text: str) -> list[ParsedSSEEvent]:
    parser = IncrementalSSEParser()
    chunk_sizes = (1, 2, 3, 5, 8, 13, 21, 34)
    position = 0
    chunk_index = 0
    while position < len(text):
        size = chunk_sizes[chunk_index % len(chunk_sizes)]
        parser.feed(text[position : position + size])
        position += size
        chunk_index += 1
    parser.feed("", final=True)
    return parser.events


def validate_stream(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ContractError("malformed_request", f"Cannot read SSE fixture: {error}") from error

    events = parse_fragmented_stream(text)
    if not events:
        raise ContractError("malformed_request", "SSE fixture contains no events")

    json_events: list[str] = []
    saw_usage = False
    terminal_type: str | None = None
    done_count = 0

    for event in events:
        if event.data == "[DONE]":
            done_count += 1
            if event.event != "message":
                raise ContractError("malformed_request", "[DONE] must use the default SSE event")
            continue

        try:
            payload = json.loads(event.data)
        except json.JSONDecodeError as error:
            raise ContractError("malformed_request", "SSE data is not valid JSON") from error
        if not isinstance(payload, dict):
            raise ContractError("malformed_request", "SSE data must decode to an object")

        event_type = validate_stream_event(payload, len(json_events))
        if event.event != event_type:
            raise ContractError("malformed_request", "SSE event name and payload type disagree")
        if event.event_id != str(payload["sequence"]):
            raise ContractError("malformed_request", "SSE id and sequence disagree")

        if event_type == "started" and json_events:
            raise ContractError("malformed_request", "started must be the first state event")
        if event_type == "usage":
            if saw_usage:
                raise ContractError("malformed_request", "usage may appear at most once")
            saw_usage = True
        if event_type in {"completed", "cancelled", "problem"}:
            if terminal_type is not None:
                raise ContractError("malformed_request", "Stream has more than one terminal event")
            terminal_type = event_type
        elif terminal_type is not None:
            raise ContractError("malformed_request", "State event appears after terminal event")

        forbidden = {"inputText", "prompt", "authorization", "credential"}
        if forbidden.intersection(payload):
            raise ContractError("malformed_request", "Stream metadata contains forbidden content")
        json_events.append(event_type)

    if not json_events or json_events[0] != "started":
        raise ContractError("malformed_request", "Stream must begin with started")
    if terminal_type not in {"completed", "cancelled"}:
        raise ContractError("malformed_request", "Canonical success fixture must terminate normally")
    if done_count != 1 or events[-1].data != "[DONE]":
        raise ContractError("malformed_request", "Stream must end with exactly one [DONE]")
    return len(json_events)


def apply_changes(value: dict[str, Any], changes: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(value)
    result.update(copy.deepcopy(changes))
    return result


def validate_invalid_cases(fixtures: dict[str, Any], now: datetime) -> int:
    valid = fixtures["valid"]
    base_claims = valid["claims"]
    base_request = valid["request"]
    base_context = fixtures["authorizationContext"]
    cases = fixtures["invalidCases"]
    if not isinstance(cases, list) or not cases:
        raise ContractError("malformed_request", "invalidCases must be a non-empty array")

    for case in cases:
        if not isinstance(case, dict):
            raise ContractError("malformed_request", "Invalid case must be an object")
        name = case.get("name")
        target = case.get("target")
        changes = case.get("changes")
        expected = case.get("expectedCode")
        if not isinstance(name, str) or target not in {"claims", "request", "context"}:
            raise ContractError("malformed_request", "Invalid test-case metadata")
        if not isinstance(changes, dict) or expected not in PROBLEM_CODES:
            raise ContractError("malformed_request", f"Invalid test-case definition: {name}")

        claims = copy.deepcopy(base_claims)
        request = copy.deepcopy(base_request)
        context = copy.deepcopy(base_context)
        if target == "claims":
            claims = apply_changes(claims, changes)
        elif target == "request":
            request = apply_changes(request, changes)
        else:
            context = apply_changes(context, changes)

        try:
            validate_request(request, now)
            validate_claims(claims, request, context, now)
        except ContractError as error:
            if error.code != expected:
                raise ContractError(
                    "internal_failure",
                    f"Case {name!r} expected {expected!r} but received {error.code!r}: {error}",
                ) from error
        else:
            raise ContractError("internal_failure", f"Case {name!r} unexpectedly passed")
    return len(cases)


def main() -> int:
    try:
        schema = load_json(SCHEMA_PATH)
        fixtures = load_json(FIXTURES_PATH)
        require_contract_version(schema.get("contractVersion"))
        require_contract_version(fixtures.get("contractVersion"))
        definitions = schema.get("$defs")
        expected_definitions = {
            "identifier",
            "uuid",
            "timestamp",
            "modelCapability",
            "workloadClaims",
            "capabilitiesResponse",
            "inferenceRequest",
            "streamEvent",
            "usageEvidence",
            "cancellationResponse",
            "problem",
        }
        if not isinstance(definitions, dict) or set(definitions) != expected_definitions:
            raise ContractError("internal_failure", "Schema definitions do not match the v1 contract set")

        now = parse_timestamp(fixtures["validationNow"], "validationNow")
        valid = fixtures["valid"]
        context = fixtures["authorizationContext"]
        request = valid["request"]
        claims = valid["claims"]

        validate_request(request, now)
        validate_claims(claims, request, context, now)
        validate_capabilities(valid["capabilities"])
        validate_usage(valid["usageEvidence"])
        validate_cancellation(valid["cancellationResponse"])
        validate_problem(valid["problem"])
        invalid_count = validate_invalid_cases(fixtures, now)
        event_count = validate_stream(STREAM_PATH)
    except (KeyError, TypeError, ContractError) as error:
        print(f"contract validation failed: {error}", file=sys.stderr)
        return 1

    print("Saturn-Node compute contract v1 validation passed")
    print("valid object types: 6")
    print(f"negative cases: {invalid_count}")
    print(f"SSE state events: {event_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
