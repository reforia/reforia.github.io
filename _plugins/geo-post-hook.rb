#!/usr/bin/env ruby
#
# GEO scaffolding: inject an answer-first TL;DR box at the top of every post
# (rendered from the `tldr` front matter) and a citation footer at the bottom.
# Rendering stays in Liquid includes (_includes/post-tldr.html,
# post-citation.html) so styling is editable without touching this plugin.
#
# Runs at :pre_render so the injected {% include %} tags are processed by Liquid
# and converted by kramdown like the rest of the post body. The guards keep it
# idempotent across Polyglot's per-language render passes.

Jekyll::Hooks.register :posts, :pre_render do |post|
  content = post.content

  unless content.include?("include post-tldr.html")
    content = "{% include post-tldr.html %}\n\n" + content
  end

  unless content.include?("include post-citation.html")
    content = content + "\n\n{% include post-citation.html %}"
  end

  post.content = content
end
