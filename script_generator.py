"""
script_generator.py — LLM Script Generator (v6 — GitHubAwesome Format)

Generates ~20-second YouTube segments for top ClawHub skills.
Format cloned from GitHubAwesome's GitHub Trending Weekly style:
  - Hook first (relatable pain / provocateur)
  - Technical specs only (no popularity metrics)
  - Dry, confident newscast energy
  - ~50 words per segment, no transitions

Supports two tracks: MOVERS (established) and ROCKETS (new <30 days).
Uses Anthropic SDK (claude-haiku-4-5 by default).
"""

import re

import anthropic
import community_signals
from datetime import datetime, timezone


# --- GitHubAwesome-style system prompt ---
# Key rules: NO popularity metrics, vivid hooks, precise technical specs, dry tone
SYSTEM_PROMPT = (
    "You write 20-second YouTube video segments about AI agent skills for OpenClaw. "
    "Your tone is dry, confident, and precise — like a tech newsreader, not a hype man. "
    "\n\n"
    "STRICT RULES:\n"
    "- Output PLAIN TEXT ONLY. No markdown, no headers, no bold, no bullet points, no formatting.\n"
    "- NEVER mention download counts, install counts, star counts, or any popularity metrics.\n"
    "- NEVER say 'Welcome back', 'check it out', 'game changer', or use filler phrases.\n"
    "- NEVER use superlatives like 'incredible', 'amazing', 'revolutionary'.\n"
    "- Lead with a vivid hook: a relatable pain point or a provocative observation.\n"
    "- Then state what it does in 1-2 precise sentences. Use concrete technical details "
    "(file formats, response times, specific CLI commands, integrations).\n"
    "- End with one sharp detail that makes the listener want to try it.\n"
    "- STRICT LIMIT: 40-55 words maximum. Count carefully. This is a 20-second read.\n"
    "- The skill name should appear naturally in the copy, not as a title.\n"
    "- Write as a single flowing paragraph. No line breaks."
)

USER_TEMPLATE_VELOCITY = """ClawHub Skill: {display_name}
Slug: {slug}
Author: {author}
Versions: {versions} | Latest: {latest_version}
Track: {track}

Summary: {summary}

Documentation:
{content}

Write a single ~20-second segment for this skill in the style described. Hook first, then what it does with precise technical details. No popularity metrics. No intro/outro."""

USER_TEMPLATE_COLD = """ClawHub Skill: {display_name}
Slug: {slug}
Author: {author}
Versions: {versions} | Latest: {latest_version}
Track: {track} (brand new skill)

Summary: {summary}

Documentation:
{content}

Write a single ~20-second segment for this brand-new skill. Hook first, then what it does with precise technical details. Emphasise what's novel about it. No popularity metrics. No intro/outro."""


def _strip_markdown(text: str) -> str:
    """Remove any markdown formatting from LLM output for voice-ready text."""
    text = re.sub(r"^#+\s+.*\n?", "", text, flags=re.MULTILINE)  # headers
    text = re.sub(r"\*\*\[?[A-Z ]+\]?\*\*\n?", "", text)  # **[HOOK]** style labels
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)  # **bold**
    text = re.sub(r"\*(.+?)\*", r"\1", text)  # *italic*
    text = re.sub(r"^[-*]\s+", "", text, flags=re.MULTILINE)  # bullet points
    text = re.sub(r"\n{2,}", " ", text)  # collapse multiple newlines
    return text.strip()


def _build_prompt(skill: dict) -> str:
    track = skill.get("_track", "mover")
    track_label = "NEW THIS WEEK" if track == "rocket" else "TOP MOVER"
    cold = skill.get("_cold_start", False)
    template = USER_TEMPLATE_COLD if cold else USER_TEMPLATE_VELOCITY

    return template.format(
        display_name=skill.get("display_name", "Unknown"),
        slug=skill.get("slug", ""),
        author=skill.get("author", "Unknown"),
        versions=skill.get("versions", 0),
        latest_version=skill.get("latest_version", ""),
        summary=skill.get("summary") or "No description.",
        content=(skill.get("content") or "No documentation available.")[:3000],
        track=track_label,
    )


def generate_scripts(
    harvested: list[dict],
    api_key: str,
    model: str = "claude-haiku-4-5-20251001",
) -> list[dict]:
    """
    Generate YouTube segment for each harvested skill.
    Returns list with 'script' field added.
    """
    client = anthropic.Anthropic(api_key=api_key)
    results = []

    for i, skill in enumerate(harvested, 1):
        name = skill.get("display_name", skill.get("slug", "?"))
        print(f"[SCRIPT] {i}/{len(harvested)} Generating segment for {name}...")

        try:
            message = client.messages.create(
                model=model,
                max_tokens=200,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": _build_prompt(skill)}],
            )
            script = _strip_markdown(message.content[0].text)
        except anthropic.APIError as e:
            print(f"  [WARN] API error for {name}: {e}")
            script = f"[Script generation failed: {e}]"

        skill["script"] = script
        results.append(skill)
        print(f"  Script: {script[:80]}...")

    return results


def render_markdown(
    movers: list[dict],
    rockets: list[dict] | None = None,
    week_label: str = "",
) -> str:
    """Render the final report with MOVERS and ROCKETS sections."""
    rockets = rockets or []

    # Determine if any movers have real velocity data
    has_velocity = any(r.get("_snapshots_used", 0) > 1 for r in movers)

    lines = [
        f"# OpenClaw Skills Weekly{' — ' + week_label if week_label else ''}",
        "",
    ]

    # --- MOVERS section ---
    if has_velocity:
        ranking_desc = "*Ranked by 7-day install velocity (installs_all_time delta).*"
    else:
        ranking_desc = "*Ranked by estimated weekly velocity (age-normalized from lifetime data — building daily history for true 7-day deltas).*"

    lines += [
        f"## Top {len(movers)} Trending Skills",
        "",
        ranking_desc,
        "",
    ]

    for i, r in enumerate(movers, 1):
        snaps = r.get("_snapshots_used", 0)
        cold = r.get("_cold_start", snaps <= 1)
        author = r.get("author", "")
        author_str = f"**Author:** {author} | " if author else ""

        if cold:
            hist = "estimated"
            pct_str = "est."
            growth_label = "Est. weekly"
        else:
            hist = f"{snaps}d data"
            pct_str = f"{r.get('_pct_increase', 0.0):.1f}%"
            growth_label = "7d Growth"

        lines += [
            f"### #{i} [{r.get('display_name', r.get('slug', '?'))}]({r.get('clawhub_url', '')})",
            "",
            (
                f"{author_str}"
                f"**Downloads:** {r.get('downloads', 0):,} | "
                f"**Installs:** {r.get('installs_current', 0):,} (all-time: {r.get('installs_all_time', 0):,}) | "
                f"**Stars:** {r.get('stars', 0)} | "
                f"**{growth_label}:** +{r.get('_installs_delta', 0):,} ({pct_str}) | "
                f"**Score:** {r.get('_score', 0.0):.4f} | "
                f"*{hist}*"
            ),
            "",
            f"> {r.get('summary', '')}" if r.get("summary") else "",
            "",
            "**YouTube Script**",
            "",
            f"_{r.get('script', '')}_",
            "",
            "---",
            "",
        ]

    # --- ROCKETS section (new skills) ---
    if rockets:
        lines += [
            "## New This Week",
            "",
            "*Brand new skills (<30 days old) showing early traction.*",
            "",
        ]
        for i, r in enumerate(rockets, 1):
            age = ""
            if r.get("created_at"):
                age_d = (datetime.now(timezone.utc) - datetime.fromtimestamp(r["created_at"] / 1000, tz=timezone.utc)).days
                age = f" | *{age_d} days old*"
            author = r.get("author", "")
            author_str = f"**Author:** {author} | " if author else ""
            lines += [
                f"### [{r.get('display_name', r.get('slug', '?'))}]({r.get('clawhub_url', '')})",
                "",
                (
                    f"{author_str}"
                    f"**Downloads:** {r.get('downloads', 0):,} | "
                    f"**Installs:** {r.get('installs_current', 0):,} | "
                    f"**Stars:** {r.get('stars', 0)} | "
                    f"**Score:** {r.get('_score', 0.0):.4f}"
                    f"{age}"
                ),
                "",
                f"> {r.get('summary', '')}" if r.get("summary") else "",
                "",
                "**YouTube Script**",
                "",
                f"_{r.get('script', '')}_",
                "",
                "---",
                "",
            ]

    # --- Community signals section ---
    signals = community_signals.load_signals()
    if signals:
        lines.append(community_signals.render_community_section(signals))

    return "\n".join(lines)


def render_video_script(
    movers: list[dict],
    rockets: list[dict] | None = None,
    episode_num: int = 1,
    week_label: str = "",
) -> str:
    """
    Render a voice-ready video script in GitHubAwesome style.

    Plain text, no markdown. Ready to read aloud or feed to TTS.
    Structure: cold open → movers → rockets → hard stop (no outro).
    """
    rockets = rockets or []
    total_skills = len(movers) + len(rockets)

    lines = []

    # --- Cold open (GitHubAwesome style) ---
    lines += [
        f"[COLD OPEN]",
        "",
        f"It is time for OpenClaw Skills Weekly, episode number {episode_num}, "
        f"featuring {total_skills} of the AI agent skills trending on ClawHub right now.",
        "",
        "",
    ]

    # --- Movers section ---
    if movers:
        lines += [
            "[TOP MOVERS]",
            "",
        ]
        for i, r in enumerate(movers, 1):
            name = r.get("display_name", r.get("slug", "?"))
            script = r.get("script", "")
            lines += [
                f"[{i}] {name}",
                "",
                script,
                "",
                "",
            ]

    # --- Rockets section ---
    if rockets:
        lines += [
            "[NEW THIS WEEK]",
            "",
        ]
        for i, r in enumerate(rockets, 1):
            name = r.get("display_name", r.get("slug", "?"))
            script = r.get("script", "")
            lines += [
                f"[NEW {i}] {name}",
                "",
                script,
                "",
                "",
            ]

    # --- No outro — last item ends the episode (GitHubAwesome style) ---
    lines += [
        "[END]",
    ]

    return "\n".join(lines)
