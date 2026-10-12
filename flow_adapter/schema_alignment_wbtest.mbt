///|
async test "published schema agrees with pinned MoonLib base contract without changing review versions" {
  let schema = @json.parse(
    @fs.read_file("schemas/conversation-review-bundle.schema.json").text(),
  )
  guard schema
    is {
      "$id": String(schema_id),
      "$defs": {
        "conversationBinding": {
          "properties": {
            "contract_id": { "const": String(base_contract), .. },
            ..
          },
          ..
        },
        ..
      },
      ..
    } else {
    fail("published bundle schema has no exact conversation contract constant")
  }
  assert_eq(base_contract, @review.conversation_contract_id())
  assert_eq(base_contract, "moonsuite-conversation.v2")
  assert_eq(schema_id, @review.input_schema_ref())
  assert_eq(
    @review.bundle_contract_id(),
    "moonchat.conversation-review-bundle.v1",
  )
  assert_eq(
    @review.record_contract_id(),
    "moonchat.conversation-review-record.v1",
  )
  assert_eq(
    @review.operation_ref(),
    "moonchat/conversation.review.record@0.1.0",
  )
  assert_eq(
    @review.output_schema_ref(),
    "moonchat/conversation-review-record@1.0.0",
  )
  let current = authored_native_fixture(
    "{\"fixture\":true}\n", "schema-fixture",
  )
  let legacy = {
    ..current,
    conversation: {
      ..current.conversation,
      contract_id: "moonsuite-conversation.v1",
    },
  }
  // Preserve structural legacy decoding; never imply legacy approval validity.
  assert_eq(@review.decode_review_bundle(legacy.to_json()), legacy)
  assert_true(
    @review.bundle_issues(legacy, legacy.source_digest).contains(
      "conversation binding must consume moonsuite-conversation.v2",
    ),
  )
}
