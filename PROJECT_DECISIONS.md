# OTIF_Guardian - Architectural Decisions

## Decision Log

### ADR-001: Project Scaffold Structure

**Date:** 2026-08-28  
**Status:** Accepted  
**Context:** Need a production-ready project layout for OTIF monitoring on Snowflake with AI capabilities.  
**Decision:** Adopted a layered structure separating SQL, semantic models, Python, Streamlit, and agent definitions into distinct directories.  
**Consequences:** Clear separation of concerns; each layer can be developed and tested independently.

---

### ADR-002: CoCo Project Memory

**Date:** 2026-08-28  
**Status:** Accepted  
**Context:** CoCo memory subsystem is disabled on this installation. Need persistent project context across sessions.  
**Decision:** Use `CORTEX.md` at project root as the instruction/memory file (standard CoCo convention for project-level instructions loaded via `enabledInstructionPatterns`).  
**Consequences:** Any CoCo session opened in the project directory will automatically load project context.

---

*Add new decisions below using the ADR template above.*
