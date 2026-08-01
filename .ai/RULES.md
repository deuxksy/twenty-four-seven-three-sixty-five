# RULES.md

This file is the Single Source of Truth (SSOT) for all runtime codebase rules in this repository.

## Core Directives
1. **Simplicity & Efficiency**: Follow KISS, YAGNI, and DRY principles.
2. **Infrastructure Validation**: Always run syntax check and validation commands before claiming task completion (`ansible-playbook --syntax-check`, `tofu validate`, `tofu fmt`).
3. **Control Flow & POSIX ACLs**: Preserved POSIX ACL permissions for shared directories (`/data/git`).
4. **Attribution & Safety**: Maintain documentation integrity, check feature flags, and never commit secrets or credentials.
