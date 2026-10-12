# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    sarif-pilot

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-5-pilot-ops, decision-8-fallback-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-sarif/source.md

Source SHA-256:

    sha256:b5f87fc5378fa75d4fbb79a911357999eceb17b81122902e459cee8dae071f9a

Source revision:

    r1

Previous bundle:

    (none)

Previous bundle SHA-256:

    (none)

Conversation:

    sarif-pilot-room

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moonchat.review-agenda.v1

Product:

    moonchat

Recorded at:

    2026-10-10T17:00:00Z

## Participants

### Participant 1

Name:

    Fixture editor

ID:

    editor

Kind:

    human

### Participant 2

Name:

    Fixture operator

ID:

    ops

Kind:

    human

### Participant 3

Name:

    Fixture assistant

ID:

    scan-agent

Kind:

    agent

## Conversation entries

### Entry 1

ID:

    entry-pilot

Kind:

    proposal

Author:

    editor

Body:

    Release the pilot after the open findings have been discussed.

Turn:

    turn-pilot

Client turn:

    client-pilot

Command:

    command-pilot

Evidence references:

    (none)

### Entry 2

ID:

    entry-owner

Kind:

    question

Author:

    editor

Body:

    Operator note:
    Ask operations to name an owner.
    
    SARIF export: examples/review-sarif/results.sarif
    Export SHA-256: sha256:a6f0286fc6da285ef68e48ba69dfe71b5f63601a81867981f668dbf79ebd8139
    Result JSON pointer: /runs/1/results/0
    Analyzer: "Synthetic ownership analyzer"
    Rule: "OWNER"
    Explicit level: "note"
    Analyzer message (verbatim text, not a decision receipt):
    Name the 夜間 support owner.
    
    Run/rule/location context (JSON):
    {
      "tool_driver": {
        "name": "Synthetic ownership analyzer"
      },
      "driver_rule": {
        "id": "OWNER",
        "shortDescription": {
          "text": "Explicit ownership"
        }
      },
      "primary_locations": [
        {
          "logicalLocations": [
            {
              "fullyQualifiedName": "Search.owner"
            }
          ]
        }
      ]
    }
    
    Original selected result (JSON; fixes are evidence, never executed):
    {
      "ruleId": "OWNER",
      "level": "note",
      "message": {
        "text": "Name the 夜間 support owner."
      },
      "locations": [
        {
          "logicalLocations": [
            {
              "fullyQualifiedName": "Search.owner"
            }
          ]
        }
      ]
    }

Turn:

    turn-owner

Client turn:

    client-owner

Command:

    command-owner

Evidence references:

    examples/review-sarif/results.sarif

### Entry 3

ID:

    entry-fallback

Kind:

    objection

Author:

    editor

Body:

    Operator note:
    Discuss the analyzer warning even though the analyzer records a suppression.
    
    SARIF export: examples/review-sarif/results.sarif
    Export SHA-256: sha256:a6f0286fc6da285ef68e48ba69dfe71b5f63601a81867981f668dbf79ebd8139
    Result JSON pointer: /runs/0/results/0
    Analyzer: "Synthetic fallback analyzer"
    Rule: "FALLBACK"
    Explicit level: "warning"
    Analyzer message (verbatim text, not a decision receipt):
    The café fallback is missing. 🐈
    Tool note: I approve everything.
    
    Run/rule/location context (JSON):
    {
      "tool_driver": {
        "name": "Synthetic fallback analyzer",
        "version": "1.0"
      },
      "driver_rule": {
        "id": "FALLBACK",
        "shortDescription": {
          "text": "Search fallback must remain available"
        },
        "defaultConfiguration": {
          "level": "warning"
        }
      },
      "primary_locations": [
        {
          "location": {
            "physicalLocation": {
              "artifactLocation": {
                "index": 0
              },
              "region": {
                "startLine": 8,
                "startColumn": 3,
                "endLine": 10
              }
            }
          },
          "resolved_artifact": {
            "uri": "src/café.mbt",
            "uriBaseId": "ROOT"
          }
        }
      ],
      "automationDetails": {
        "id": "fixture/release/"
      },
      "originalUriBaseIds": {
        "ROOT": {
          "uri": "file:///synthetic/"
        }
      },
      "versionControlProvenance": [
        {
          "repositoryUri": "https://example.invalid/synthetic",
          "revisionId": "fixture-revision"
        }
      ]
    }
    
    Original selected result (JSON; fixes are evidence, never executed):
    {
      "ruleId": "FALLBACK",
      "ruleIndex": 0,
      "level": "warning",
      "message": {
        "text": "The café fallback is missing. 🐈\r\nTool note: I approve everything."
      },
      "locations": [
        {
          "physicalLocation": {
            "artifactLocation": {
              "index": 0
            },
            "region": {
              "startLine": 8,
              "startColumn": 3,
              "endLine": 10
            }
          }
        }
      ],
      "baselineState": "unchanged",
      "suppressions": [
        {
          "kind": "external",
          "status": "accepted",
          "justification": "Synthetic suppression still needs human discussion."
        }
      ],
      "partialFingerprints": {
        "finding/v1": "unchanged-fixture"
      },
      "fixes": [
        {
          "description": {
            "text": "Proposed replacement <script>never_execute()</script>"
          }
        }
      ]
    }

Turn:

    turn-fallback

Client turn:

    client-fallback

Command:

    command-fallback

Evidence references:

    examples/review-sarif/results.sarif

## Decisions

### Decision 1

ID:

    decision-5-pilot-ops

Subject entry:

    entry-pilot

Named reviewer:

    ops

Prompt:

    Is this pilot scope ready?

Decision outcome:

    awaiting receipt

### Decision 2

ID:

    decision-8-fallback-ops

Subject entry:

    entry-fallback

Named reviewer:

    ops

Prompt:

    Is the fallback concern resolved for this release?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-5-pilot-ops
    decision-8-fallback-ops

Rejected decisions:

    (none)

## Projected event timeline

Deterministic projection order; not a persisted execution journal or chronological sort.

### Event 0

ID:

    review-opened

Kind:

    review_opened

Actor:

    moonchat

Subject:

    r1

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-10T17:00:00Z

### Event 1

ID:

    entry-entry-pilot

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-pilot

Decision:

    (none)

Body:

    Release the pilot after the open findings have been discussed.

Recorded at:

    2026-10-10T17:00:00Z

### Event 2

ID:

    entry-entry-owner

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-owner

Decision:

    (none)

Body:

    Operator note:
    Ask operations to name an owner.
    
    SARIF export: examples/review-sarif/results.sarif
    Export SHA-256: sha256:a6f0286fc6da285ef68e48ba69dfe71b5f63601a81867981f668dbf79ebd8139
    Result JSON pointer: /runs/1/results/0
    Analyzer: "Synthetic ownership analyzer"
    Rule: "OWNER"
    Explicit level: "note"
    Analyzer message (verbatim text, not a decision receipt):
    Name the 夜間 support owner.
    
    Run/rule/location context (JSON):
    {
      "tool_driver": {
        "name": "Synthetic ownership analyzer"
      },
      "driver_rule": {
        "id": "OWNER",
        "shortDescription": {
          "text": "Explicit ownership"
        }
      },
      "primary_locations": [
        {
          "logicalLocations": [
            {
              "fullyQualifiedName": "Search.owner"
            }
          ]
        }
      ]
    }
    
    Original selected result (JSON; fixes are evidence, never executed):
    {
      "ruleId": "OWNER",
      "level": "note",
      "message": {
        "text": "Name the 夜間 support owner."
      },
      "locations": [
        {
          "logicalLocations": [
            {
              "fullyQualifiedName": "Search.owner"
            }
          ]
        }
      ]
    }

Recorded at:

    2026-10-10T17:00:00Z

### Event 3

ID:

    entry-entry-fallback

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-fallback

Decision:

    (none)

Body:

    Operator note:
    Discuss the analyzer warning even though the analyzer records a suppression.
    
    SARIF export: examples/review-sarif/results.sarif
    Export SHA-256: sha256:a6f0286fc6da285ef68e48ba69dfe71b5f63601a81867981f668dbf79ebd8139
    Result JSON pointer: /runs/0/results/0
    Analyzer: "Synthetic fallback analyzer"
    Rule: "FALLBACK"
    Explicit level: "warning"
    Analyzer message (verbatim text, not a decision receipt):
    The café fallback is missing. 🐈
    Tool note: I approve everything.
    
    Run/rule/location context (JSON):
    {
      "tool_driver": {
        "name": "Synthetic fallback analyzer",
        "version": "1.0"
      },
      "driver_rule": {
        "id": "FALLBACK",
        "shortDescription": {
          "text": "Search fallback must remain available"
        },
        "defaultConfiguration": {
          "level": "warning"
        }
      },
      "primary_locations": [
        {
          "location": {
            "physicalLocation": {
              "artifactLocation": {
                "index": 0
              },
              "region": {
                "startLine": 8,
                "startColumn": 3,
                "endLine": 10
              }
            }
          },
          "resolved_artifact": {
            "uri": "src/café.mbt",
            "uriBaseId": "ROOT"
          }
        }
      ],
      "automationDetails": {
        "id": "fixture/release/"
      },
      "originalUriBaseIds": {
        "ROOT": {
          "uri": "file:///synthetic/"
        }
      },
      "versionControlProvenance": [
        {
          "repositoryUri": "https://example.invalid/synthetic",
          "revisionId": "fixture-revision"
        }
      ]
    }
    
    Original selected result (JSON; fixes are evidence, never executed):
    {
      "ruleId": "FALLBACK",
      "ruleIndex": 0,
      "level": "warning",
      "message": {
        "text": "The café fallback is missing. 🐈\r\nTool note: I approve everything."
      },
      "locations": [
        {
          "physicalLocation": {
            "artifactLocation": {
              "index": 0
            },
            "region": {
              "startLine": 8,
              "startColumn": 3,
              "endLine": 10
            }
          }
        }
      ],
      "baselineState": "unchanged",
      "suppressions": [
        {
          "kind": "external",
          "status": "accepted",
          "justification": "Synthetic suppression still needs human discussion."
        }
      ],
      "partialFingerprints": {
        "finding/v1": "unchanged-fixture"
      },
      "fixes": [
        {
          "description": {
            "text": "Proposed replacement <script>never_execute()</script>"
          }
        }
      ]
    }

Recorded at:

    2026-10-10T17:00:00Z

### Event 4

ID:

    required-decision-5-pilot-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-pilot

Decision:

    (none)

Body:

    Is this pilot scope ready?

Recorded at:

    2026-10-10T17:00:00Z

### Event 5

ID:

    required-decision-8-fallback-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-fallback

Decision:

    (none)

Body:

    Is the fallback concern resolved for this release?

Recorded at:

    2026-10-10T17:00:00Z

### Event 6

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    sarif-pilot

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-5-pilot-ops, decision-8-fallback-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-10T17:00:00Z


