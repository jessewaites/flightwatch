# Agent-runtime dependencies. The Rails UI has its own Gemfile in ui/.
# The data and enrichment layers use only the Ruby stdlib (net/http, json, csv).
source "https://rubygems.org"

ruby ">= 3.2"

# Watcher -> local Ollama (granite4:micro); Investigator/Synthesizer -> Anthropic (online mode).
# The agents `require "ruby_llm"` lazily, so this is only needed for non-offline runs.
gem "ruby_llm", "~> 1.15"
