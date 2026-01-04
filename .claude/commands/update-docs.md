# Update Documentation Based on Changes

Examine the current working tree to understand what changes have been made, then create a comprehensive plan to update all relevant documentation.

## Steps to follow:

1. **Analyze the working tree:**
   - Run `git status` to see what files have changed
   - Run `git diff` to see the actual changes in modified files
   - Review any new untracked files

2. **Identify documentation impact:**
   - Determine which changes affect user-facing behavior
   - Identify new features, removed features, or modified functionality
   - Note any changes to APIs, configuration, or interfaces
   - Look for existing documentation that may now be outdated
   - **Skip internal refactoring**: Don't document file renames, code reorganization, or internal refactoring unless it affects user-facing behavior

3. **Create a documentation update plan:**
   - Create a `docs-update.todo.md` file with the plan
   - Use TodoWrite() to track the plan in the UI
   - Break the plan into logical phases:
     - README updates (if applicable)
     - Code documentation/comments updates
     - Architecture or design docs updates
     - Configuration or setup guide updates
     - Any other relevant documentation

4. **For each documentation update:**
   - Identify the specific files that need updating
   - Describe what needs to be added, modified, or removed
   - Ensure mermaid diagrams are updated if architecture changed
   - Verify examples and code snippets still work

5. **Present the plan:**
   - Show me the complete plan before executing
   - Ask if I want to proceed with the updates or modify the plan

Remember: Focus on documentation that will help users understand and use the changes effectively. Don't update documentation for:
- Trivial changes unless they impact usage or understanding
- File renames or moves (unless the user needs to know about new file locations)
- Internal refactoring or code reorganization
- Changes to internal implementation details that don't affect the user API
