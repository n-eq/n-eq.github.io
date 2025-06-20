# adapted from https://github.com/memfault/interrupt/blob/81025f582d1973fd6f7a154e97b19e070709b8d6/_plugins/tag_url.rb

module Jekyll
  module TagHelpers
    def tag_url(tag)
      slug = tag.to_s.downcase.strip.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
      relative_url("/tag/#{slug}")
    end

    def sort_tags_by_count(tags)
      tags.sort_by { |tag, posts| -posts.size }
    end
  end
end

Liquid::Template.register_filter(Jekyll::TagHelpers)

