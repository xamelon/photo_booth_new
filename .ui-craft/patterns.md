# UI patterns

Append-only contracts for reusable admin UI shapes. New admin screens should use these before adding page-specific CSS.

## Admin typography contract

Use the existing system font stack. Do not add a webfont unless the product needs brand personality outside the admin UI.

Rules:
- Headings use `h1/h2` defaults; do not hand-size headings per page.
- Page descriptions use `.page-subtitle` or `.hint-text`.
- Table counts and numeric columns use `.num`.
- IDs, timestamps, JSON, payloads use `.mono-cell` or `code`.
- Labels use 12px semibold with token tracking; avoid ad-hoc uppercase except table headers and nav groups.
- New CSS should use `--text-*`, `--leading-*`, `--tracking-*`, and font weight tokens, not raw font values.

Why: this admin is an operator tool. Typography should make state and data scan fast, not create decorative hierarchy.

## Button density

Default admin buttons are compact controls, not marketing CTAs.

Rules:
- Generic `button` height target is ~30px.
- Use `.compact-button` for table/list row actions: ~26px, 12px text.
- Use `.danger-link-button` for destructive row actions; avoid large red pills in data tables.
- Do not put `display:flex` directly on table cells for actions; keep table cells as table cells and style the inner form/button.

Why: large buttons dominate data/state and make admin tables look broken.

## Dense filter bar

Use for table/list filtering on runtime admin pages.

```heex
<form method="get" action={@path} class="filter-bar filter-bar--dense">
  <label class="field-stack field-stack--compact">
    <span>Status</span>
    <select name="status" class="control control--select">
      <option value="">all statuses</option>
    </select>
  </label>

  <label class="field-stack field-stack--compact field-stack--search">
    <span>External ID</span>
    <input class="control" name="q" placeholder="external id" />
  </label>

  <div class="filter-actions">
    <button class="secondary-button compact-button">Filter</button>
    <a class="inline-link" href={@path}>clear</a>
  </div>
</form>
```

Rules:
- Every visible input/select sits inside `.field-stack.field-stack--compact` with a label.
- Use `.control` on inputs/selects; `.control--select` on selects.
- Use `.field-stack--search` for wider text search fields.
- Put submit/reset links in `.filter-actions`.
- Do not place bare inputs/selects directly in `.filter-bar`.

Why: filters are operational controls, not decorative layout. Equal heights, labels, and widths preserve scan speed across Inbox, Outbox, Sessions, Events, and future queue pages.
