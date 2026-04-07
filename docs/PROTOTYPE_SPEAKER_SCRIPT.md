# Prototype Speaker Script (Live Read)

Use this as a literal run sheet during the prototype showing meeting.

## Total target: 12-15 minutes

---

## 0:00 - 0:45 Opening

**Say**

- "Today is a prototype showing of our local-first editorial review flow."
- "We are intentionally running in deterministic local mode to reduce demo risk."

**Do**

- Launch desktop app.
- If auth appears, click **Continue Offline**.

---

## 0:45 - 2:00 Desktop walkthrough (quick)

**Say**

- "I will run a short built-in walkthrough so new users can self-onboard."

**Do**

- If walkthrough appears, click **Next** through first 2-3 cards.
- Mention: **Enter** advances, **Esc** skips.
- Press `Command+Shift+W` once to replay and prove discoverability, then skip.

---

## 2:00 - 4:30 Import and browse footage

**Say**

- "Now I will import sample presentation footage from our demo fixture folder."
- "Search and filter are tuned for fast shot discovery."

**Do**

- Import from `demo-assets/sample-presentation-footage/`.
- In clip browser: type in search, apply one status filter, select hero clip.

---

## 4:30 - 6:30 Clip detail + playback

**Say**

- "This is local proxy playback with sync and AI review context available in tabs."

**Do**

- Open selected clip detail.
- Play a few seconds, pause.
- Click through tabs: Preview -> Sync -> AI -> Annotations.

---

## 6:30 - 8:30 Multicam (if grouped clip exists)

**Say**

- "For multicam, we can compare angles and quickly mark the best take."

**Do**

- Open multicam group.
- Play/pause once.
- Click **Circle Best**.
- Close multicam and return.

If no multicam:

- "This fixture has no multicam group loaded; the same flow works when grouped angles are present."

---

## 8:30 - 10:00 Shortcuts + customizable toolbar

**Say**

- "We added hover hints and shortcuts for high-frequency producer actions."
- "Toolbar controls are customizable per operator."

**Do**

- Show tooltip on 1-2 toolbar buttons.
- Trigger one shortcut (example: `Command+I` for ingest progress).
- Open toolbar customization (`Command+Shift+T`), move one action, click **Done**.

---

## 10:00 - 13:00 Web review walkthrough

**Say**

- "Now the same review semantics in web: playback, notes, and status."

**Do**

- Open web review route.
- Show walkthrough (press `?` if needed).
- Select a clip, play/pause with `K`, jump with `J/L`.
- Add one annotation.
- Set one status action.
- Show quick actions strip and open customize panel briefly.

---

## 13:00 - 14:30 Reliability close

**Say**

- "If cloud services are unavailable, local review remains functional."
- "This gives us a stable prototype path for production demos."

**Do**

- Point to local-first behavior (no blocking cloud dependency).
- End on active clip with status + note visible.

---

## Fast fallback lines (use as needed)

- "Cloud path is optional in this prototype; we’ll continue local-first."
- "I’ll switch to a backup clip to keep the flow moving."
- "This action is available via both shortcut and UI control."