---
name: optimize-review
description: Review the results of the most recent codeflash optimization run
allowed-tools: Read, Glob, Grep, Bash
---

Review the most recent codeflash optimization results.

Use the result-reviewer agent's approach:

1. Look in the current conversation for codeflash output from a background task completion
2. If output is available, parse and review it:
   - Identify which functions were optimized and the speedup achieved
   - Read the original source files to understand what changed
   - Explain each optimization in plain language
   - Assess safety and trade-offs
3. Present a structured summary with recommendations
4. If no codeflash output is found in the conversation, tell the user to run `/optimize` first and then use `/optimize-review` after it completes
