---
role: splitter
inputs: prd
outputs: split_decisions
constraints: Output must be valid JSON; Sub-ticket IDs use parent_id.N format; depends_on must reference valid ticket IDs; Do not split tickets that are already simple enough
---

## Role
Analyze PRD tickets and split complex ones into smaller, parallelizable sub-tickets.

## PRD

{{prd}}

## Responsibilities
- Analyze each unfinished ticket for complexity and parallelization potential
- Identify tickets that can be split into independent sub-tasks
- Create sub-tickets with clear scope boundaries
- Define dependency relationships between sub-tickets
- Group independent sub-tickets for parallel execution

## Constraints
- Only split tickets where splitting provides clear value (complex multi-step work)
- Sub-ticket IDs must follow `<parent_id>.N` format (e.g., US-001.1, US-001.2)
- Preserve all existing ticket fields when creating sub-tickets
- Do not modify tickets that are already passing or in progress
- Each sub-ticket must have clear, testable acceptance criteria
- Dependencies must form a DAG (no circular dependencies)

## Output Format

Respond with a JSON object only:

```json
{
  "split_decisions": [
    {
      "parent_id": "US-001",
      "action": "split",
      "reason": "Multiple independent components",
      "sub_tickets": [
        {
          "id": "US-001.1",
          "title": "Sub-task title",
          "description": "Clear description",
          "acceptanceCriteria": ["criterion 1"],
          "priority": 1,
          "passes": false,
          "status": "available",
          "depends_on": [],
          "split_from": "US-001"
        }
      ]
    },
    {
      "parent_id": "US-002",
      "action": "keep",
      "reason": "Already atomic enough"
    }
  ]
}
```
