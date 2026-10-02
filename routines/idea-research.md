# 💡 Idea research routine (template)

A scheduled Claude task that researches trends every few hours, writes **ideas for your brand or project**,
and lets Clawd pitch them one at a time in a "💡 Idea!" bubble (menu bar, Touch Bar or floating).

## How to set it up

1. Copy the task below and replace every `[bracket]` with your own details.
2. In the Claude desktop app, open any Code session and say:
   > Create a scheduled task that runs this every 3 hours, from 9 am to 9 pm.
   > (paste your edited task)
3. Run it once right away and allow web search and file writing, so later runs don't stop to ask.

Scheduled tasks run while the Claude app is open, or on the next launch if it was closed. Each run uses your Claude usage.

## The task

```
#clawd-idea-routine
(Keep the tag above. It tells Clawd this is the idea routine, so it pitches ideas instead of showing "Done!".)

## Goal
Research the most creative, surprising content with great views, shares and saves on [where: e.g. US Instagram Reels right now],
then turn it into content and planning ideas for "[brand name]". Leave one report plus the idea list Clawd reads.

## About [brand name]
[one or two lines: e.g. a newsletter about remote work, @handle]
Topics: [e.g. remote work, side projects, AI tools, travel while working]
Format & voice: [e.g. short Reels and carousels, friendly and casual]

## 1. Get context (briefly)
- Read [folder with your past content] to learn your topics and tone.
- Read ~/.clawd-touchbar/ideas.json and the last 3 reports in [report folder], and don't repeat earlier ideas.
- Other topics: from .jsonl files under ~/.claude/projects/ changed in the last 3 days, collect the customTitle of lines with
  "type":"custom-title" to see what you're working on with Claude. Pick up to 2 (skip this routine and one-off cleanup tasks).

## 2. Research (web search and reading only)
- Prefer sources from the last 7–14 days: official trend reports, weekly trend posts from marketing sites, and similar.
- Pick 3–5 inventive formats, hooks, edits or audio uses. Favor types that get shared and saved (save-for-later info, tag-a-friend, twist or meme).
- Only quote view, share or save numbers that are public, with the source. If there are none, write "no public numbers". Never make numbers up.

## 3. Ideas
- 3 ideas for [brand name]: title (max 60 characters), format, first-3-seconds hook, structure (4–6 shots or slides),
  first caption line + hashtags, and the trend it borrows with a source link.
- 1 idea for each extra topic from step 1 (title + 2–3 sentences).

## 4. Save the report
Save `YYYY-MM-DD HHmm trends.md` in [report folder].
Sections: standout trends (what, why it works, public numbers, sources) → [brand name] ideas → other ideas → limitations.

## 5. Hand ideas to Clawd
Update ~/.clawd-touchbar/ideas.json: put the new ideas first and keep the latest 40. Format:
{"ideas": [{"id": "YYYYMMDD-HHmm-N", "topic": "[brand name] (or the short session title)", "title": "one line, max 60 characters",
 "detail": "max 160 characters: format, hook, borrowed trend", "report": "absolute path of the report you just saved", "created": "ISO 8601 time with offset"}]}
Write to a temporary file in the same folder first, then rename it over the original so the JSON never breaks.

## Rules
- Only read the web. Don't log in anywhere, and don't post or send anything.
- Don't create or change any files except the report and ideas.json.
- End your final answer with the titles of the 3 ideas, one per line.
```
