package mdz

// Feature flags — set at compile time via Odin's -define mechanism.
// Features are enabled by default; disable selectively:
//   odin build . -define:mdz.Tables=false -define:mdz.Math=false
//
// When a feature is disabled, its block classification and processing
// are compiled out entirely — zero runtime cost.

Tables :: #config(Tables, true)
Math :: #config(Math, true)
Highlight :: #config(Highlight, true)
Emoji :: #config(Emoji, true)
Comment :: #config(Comment, true)
DefList :: #config(DefList, true)
Autolink :: #config(Autolink, true)
TaskList :: #config(TaskList, true)
Footnote :: #config(Footnote, true)
ReferenceLink :: #config(ReferenceLink, true)
