import "package:flutter/material.dart";

/// Value is 320px(S).
const int windowCompactSmall = 320;

/// Value is 375px(M).
const int windowCompactMedium = 375;

/// Value is 425px(L).
const int windowCompactLarge = 425;

/// Value is 600(under 600px).
const int windowCompact = 600;

/// Value is 840(under 840px).
const int windowMedium = 840;

// List of LLM prompt hints.
//
// Fantasy.
const String blurbPromptHint = "Write a blurb about this new soda beverage.";
// Romance.
const String emailPromptHint =
    "Craft an email to a coworker working in Antartica.";
// Scifi
const String scifiPromptHint =
    "In the neon-lit underbelly of the metropolis, beneath layers of augmented reality, she hacked the corporate mainframe. Her mission: to uncover the elusive truth buried within the digital labyrinth. As she delved deeper, she realized the secrets held a power that could reshape their dystopian world.";
// Brainstorm.
const String brainstormPromptHint =
    "Give me a list of 3 science fiction books I should read next.";
// Tool-Search.
const String toolSearchPromptHint = "Search web for this query: ";
// Tool-Math(elementary,middle,college,professional).
const String toolMathPromptHint =
    "what is 1 + 1? explain step-by-step concisely";
// Open QnA.
const String openQNAPromptHint =
    "How do I build a campfire? explain step-by-step concisely";
const String systemPromptHint = "Describe yourself in detail.";
// Closed QnA.
const String closedQNAPromptHint =
    "Explain to me concisely the difference between nuclear fission and fusion.";
