# isme.gg project instructions

## Public releases: mandatory What's New approval
Before preparing or publishing any new public release, ask the project owner what content and interactions should appear in that version's What's New modal. Do not assume that release notes are the modal copy or reuse an earlier release's widget without explicit approval. If the owner has already approved the exact content for that version in the current release work, do not ask again. Record the approved version-specific design in its release widget and register a unique builder in `lib/whats_new/whats_new_registry.dart` for the exact version+versionCode. Run `python3 tools/check_whats_new.py` and test the modal on mobile and TV, including persisted acknowledgment and actions. Do not publish a public release without explicit owner authorization.

The modal may contain custom widgets, text, images, buttons or configuration controls. Keep acknowledgment local to the installed version. Maintain the debug preview for emulator testing. Do not force experimental playback on users; Legacy HTTP is the default unless they opt in.
