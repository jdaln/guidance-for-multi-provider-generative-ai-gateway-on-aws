"""
Proposed unit tests for the middleware/app.py Converse->OpenAI conversion
helpers (upstream issue #123).

Upstream placement: tests/middleware/test_converse_compat.py, with a
conftest.py that sets AWS_DEFAULT_REGION before `import app` (app.py builds a
boto3 client at import time) and tests/requirements.txt pulling in
-r ../middleware/requirements.txt.

The module under test is selectable so the same suite runs against the
standalone patched copy (default) and against the patched app.py:

    CONVERSE_COMPAT_MODULE=app AWS_DEFAULT_REGION=eu-north-1 pytest test_bedrock_compat.py
"""
import asyncio
import importlib
import os

import pytest

MOD = importlib.import_module(os.environ.get("CONVERSE_COMPAT_MODULE", "bedrock_compat_patched"))
HTTPException = MOD.HTTPException
convert_messages_to_openai = MOD.convert_messages_to_openai
convert_openai_to_bedrock_history = MOD.convert_openai_to_bedrock_history
split_params_for_openai_sdk = MOD.split_params_for_openai_sdk


def convert_bedrock_to_openai_sync(model, body, streaming):
    fn = getattr(MOD, "convert_bedrock_to_openai_sync", None)
    if fn is not None:
        return fn(model, body, streaming)
    return asyncio.run(MOD.convert_bedrock_to_openai(model, body, streaming))


def _error(exc: HTTPException) -> str:
    detail = exc.detail
    return detail["error"] if isinstance(detail, dict) else str(detail)


# --- the exact request body from issue #123 (boto3 converse() JSON) -------------
ISSUE_123_BODY = {
    "messages": [
        {
            "role": "user",
            "content": [{"guardContent": {"text": {"text": "How's the weather?"}}}],
        }
    ],
    "system": [{"text": "You are a cool cat"}],
    "inferenceConfig": {"maxTokens": 4096, "temperature": 1.0},
    "additionalModelRequestFields": {},
    "guardrailConfig": {
        "guardrailIdentifier": "YOUR-BEDROCK-GUARDRAIL-ID",
        "guardrailVersion": "DRAFT",
        "trace": "enabled_full",
    },
}


def test_issue_123_guardcontent_is_not_dropped():
    msgs = convert_messages_to_openai(ISSUE_123_BODY["messages"], ISSUE_123_BODY["system"])
    assert msgs == [
        {"role": "system", "content": "You are a cool cat"},
        {"role": "user", "content": [{"type": "guarded_text", "text": "How's the weather?"}]},
    ]
    assert msgs[1]["content"] != ""  # regression guard for the empty user message


def test_issue_123_guardrail_config_is_forwarded():
    params = convert_bedrock_to_openai_sync(
        "us.anthropic.claude-3-5-sonnet-20241022-v2:0", ISSUE_123_BODY, True
    )
    assert params["guardrailConfig"] == ISSUE_123_BODY["guardrailConfig"]
    assert params["stream"] is True
    assert params["max_tokens"] == 4096 and params["temperature"] == 1.0
    # streaming path: guardrailConfig must ride in extra_body for the OpenAI SDK
    sdk_kwargs = split_params_for_openai_sdk(params)
    assert "guardrailConfig" not in sdk_kwargs
    assert sdk_kwargs["extra_body"]["guardrailConfig"]["trace"] == "enabled_full"
    assert sdk_kwargs["messages"] == params["messages"]


def test_single_text_block_keeps_legacy_string_form():
    msgs = convert_messages_to_openai([{"role": "user", "content": [{"text": "Hello"}]}])
    assert msgs == [{"role": "user", "content": "Hello"}]


def test_multiple_text_blocks_are_not_concatenated_without_separator():
    # sibling bug: upstream produced "HelloWorld"
    msgs = convert_messages_to_openai(
        [{"role": "user", "content": [{"text": "Hello"}, {"text": "World"}]}]
    )
    assert msgs[0]["content"] == [
        {"type": "text", "text": "Hello"},
        {"type": "text", "text": "World"},
    ]


def test_mixed_text_and_guardcontent_preserves_order():
    msgs = convert_messages_to_openai(
        [
            {
                "role": "user",
                "content": [
                    {"text": "Summarise this:"},
                    {"guardContent": {"text": {"text": "sensitive passage", "qualifiers": ["guard_content"]}}},
                    {"text": "Thanks."},
                ],
            }
        ]
    )
    assert msgs[0]["content"] == [
        {"type": "text", "text": "Summarise this:"},
        {"type": "guarded_text", "text": "sensitive passage"},  # qualifiers dropped (documented)
        {"type": "text", "text": "Thanks."},
    ]


def test_image_block_maps_to_data_uri():
    msgs = convert_messages_to_openai(
        [
            {
                "role": "user",
                "content": [
                    {"text": "What is this?"},
                    {"image": {"format": "png", "source": {"bytes": "iVBORw0KGgo="}}},
                ],
            }
        ]
    )
    assert msgs[0]["content"][1] == {
        "type": "image_url",
        "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="},
    }


@pytest.mark.parametrize(
    "block",
    [
        {"toolUse": {"toolUseId": "t1", "name": "f", "input": {}}},
        {"toolResult": {"toolUseId": "t1", "content": [{"text": "x"}]}},
        {"document": {"format": "pdf", "name": "d", "source": {"bytes": "AA=="}}},
        {"video": {"format": "mp4", "source": {"bytes": "AA=="}}},
    ],
)
def test_unsupported_blocks_return_400_with_block_name(block):
    with pytest.raises(HTTPException) as exc:
        convert_messages_to_openai([{"role": "user", "content": [{"text": "hi"}, block]}])
    assert exc.value.status_code == 400
    key = next(iter(block))
    assert key in _error(exc.value)
    assert "messages[0].content[1]" in _error(exc.value)


@pytest.mark.parametrize(
    "content",
    [[], [{"text": ""}], [{"text": "   "}], [{"guardContent": {"text": {"text": ""}}}]],
)
def test_empty_content_returns_400_instead_of_empty_user_message(content):
    with pytest.raises(HTTPException) as exc:
        convert_messages_to_openai([{"role": "user", "content": content}])
    assert exc.value.status_code == 400
    assert "no non-empty content" in _error(exc.value)


def test_system_guardcontent_is_extracted_and_blocks_joined_with_newline():
    msgs = convert_messages_to_openai(
        [{"role": "user", "content": [{"text": "hi"}]}],
        system=[{"text": "Rule one."}, {"guardContent": {"text": {"text": "Rule two."}}}],
    )
    assert msgs[0] == {"role": "system", "content": "Rule one.\nRule two."}


def test_assistant_history_messages_convert_too():
    msgs = convert_messages_to_openai(
        [
            {"role": "user", "content": [{"text": "hi"}]},
            {"role": "assistant", "content": [{"text": "hello"}]},
            {"role": "user", "content": [{"guardContent": {"text": {"text": "again"}}}]},
        ]
    )
    assert [m["role"] for m in msgs] == ["user", "assistant", "user"]
    assert msgs[1]["content"] == "hello"


def test_invalid_guardrail_config_returns_400():
    body = {
        "messages": [{"role": "user", "content": [{"text": "hi"}]}],
        "guardrailConfig": {"guardrailVersion": "1"},
    }
    with pytest.raises(HTTPException) as exc:
        convert_bedrock_to_openai_sync("m", body, False)
    assert exc.value.status_code == 400


def test_additional_model_request_fields_go_to_extra_body_for_sdk():
    body = {
        "messages": [{"role": "user", "content": [{"text": "hi"}]}],
        "additionalModelRequestFields": {"top_k": 5, "session_id": "s", "enable_history": True},
    }
    params = convert_bedrock_to_openai_sync("m", body, True)
    assert "session_id" not in params and "enable_history" not in params
    sdk_kwargs = split_params_for_openai_sdk(params)
    assert sdk_kwargs["extra_body"] == {"top_k": 5}


def test_history_round_trip_handles_list_content():
    history = [
        {"role": "system", "content": "sys"},
        {"role": "user", "content": [{"type": "guarded_text", "text": "g"}, {"type": "text", "text": "t"}]},
        {"role": "assistant", "content": "a"},
    ]
    out = convert_openai_to_bedrock_history(history)
    assert out["system"] == [{"text": "sys"}]
    assert out["messages"][0] == {
        "role": "user",
        "content": [{"guardContent": {"text": {"text": "g"}}}, {"text": "t"}],
    }
    assert out["messages"][1] == {"role": "assistant", "content": [{"text": "a"}]}
