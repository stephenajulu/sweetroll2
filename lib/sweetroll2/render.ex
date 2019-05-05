defmodule Sweetroll2.Render.Tpl do
  defmacro deftpl(name, file) do
    quote do
      EEx.function_from_file(:def, unquote(name), unquote(file), [:assigns],
        engine: Phoenix.HTML.Engine
      )
    end
  end
end

defmodule Sweetroll2.Render do
  alias Sweetroll2.{Doc, Markup}
  import Sweetroll2.Convert
  import Sweetroll2.Render.Tpl
  import Phoenix.HTML.Tag
  import Phoenix.HTML
  require EEx

  deftpl :head, "tpl/head.html.eex"
  deftpl :header, "tpl/header.html.eex"
  deftpl :footer, "tpl/footer.html.eex"
  deftpl :entry, "tpl/entry.html.eex"
  deftpl :cite, "tpl/cite.html.eex"
  deftpl :page_entry, "tpl/page_entry.html.eex"
  deftpl :page_feed, "tpl/page_feed.html.eex"

  @doc """
  Renders a document, choosing the right template based on its type.

  - `doc`: current document
  - `preload`: `Access` object for retrieval of docs by URL (all fetched docs or `Cache`)
  - `allu`: *A*t *L*east *L*ocal *U*RLs -- `Enumerable` of either known local URLs or all known URLs
  """
  def render_doc(doc: doc = %Doc{}, params: params, preload: preload, allu: allu) do
    feed_urls = Doc.filter_feeds(allu, preload)

    cond do
      doc.type == "entry" || doc.type == "review" ->
        doc = Doc.inline_comments(doc, preload)
        page_entry(entry: doc, preload: preload, feed_urls: feed_urls)

      doc.type == "x-dynamic-feed" ->
        page = params[:page] || 0
        children = Doc.filter_feed_entries(doc, preload, allu)

        page_children =
          Enum.slice(children, page * 10, 10)
          |> Enum.map(&Doc.inline_comments(&1, preload))

        # IO.inspect Doc.dynamic_urls(preload, allu)

        page_feed(
          feed: %{doc | children: page_children},
          preload: preload,
          feed_urls: feed_urls,
          per_page: 10,
          page_count: Doc.feed_page_count(children),
          cur_page: page
        )

      true ->
        {:error, :unknown_type, doc.type}
    end
  end

  def asset(url) do
    "/as/#{url}"
  end

  def icon(data) do
    content_tag :svg,
      role: "image",
      "aria-hidden": if(data[:title], do: "false", else: "true"),
      class: Enum.join([:icon] ++ (data[:class] || []), " "),
      title: data[:title] do
      content_tag :use, "xlink:href": "#{asset("icons.svg")}##{data[:name]}" do
        if data[:title] do
          content_tag :title do
            data[:title]
          end
        end
      end
    end
  end

  def reaction_icon(:replies), do: "reply"
  def reaction_icon(:likes), do: "star"
  def reaction_icon(:reposts), do: "megaphone"
  def reaction_icon(:quotations), do: "quote"
  def reaction_icon(:bookmarks), do: "bookmark"
  def reaction_icon(_), do: "link"

  def reaction_class(:replies), do: "reply"
  def reaction_class(:likes), do: "like"
  def reaction_class(:reposts), do: "repost"
  def reaction_class(:quotations), do: "quotation"
  def reaction_class(:bookmarks), do: "bookmark"
  def reaction_class(_), do: "comment"

  def time_permalink(%Doc{published: published, url: url}, rel: rel) do
    use Taggart.HTML

    if published do
      time datetime: DateTime.to_iso8601(published), class: "dt-published" do
        a href: url, class: "u-url u-uid", rel: rel do
          published
        end
      end
    end
  end

  def trim_url_stuff(url) do
    url
    |> String.replace_leading("http://", "")
    |> String.replace_leading("https://", "")
    |> String.replace_trailing("/", "")
  end

  def client_id(clid) do
    use Taggart.HTML

    lnk = as_one(clid)

    a href: lnk, class: "u-client-id" do
      trim_url_stuff(lnk)
    end
  end

  def syndication_name(url) do
    cond do
      String.contains?(url, "indieweb.xyz") -> "Indieweb.xyz"
      String.contains?(url, "news.indieweb.org") -> "IndieNews"
      String.contains?(url, "lobste.rs") -> "lobste.rs"
      String.contains?(url, "news.ycombinator.com") -> "HN"
      String.contains?(url, "twitter.com") -> "Twitter"
      String.contains?(url, "tumblr.com") -> "Tumblr"
      String.contains?(url, "facebook.com") -> "Facebook"
      String.contains?(url, "instagram.com") -> "Instagram"
      String.contains?(url, "swarmapp.com") -> "Swarm"
      true -> trim_url_stuff(url)
    end
  end

  def doc_title(doc) do
    doc.props["name"] || DateTime.to_iso8601(doc.published)
  end

  def responsive_container(media, do: body) when is_map(media) do
    use Taggart.HTML

    is_resp = is_integer(media["width"]) && is_integer(media["height"])
    cls = if is_resp, do: "responsive-container", else: ""

    col =
      case as_one(
             Enum.sort_by(media["palette"] || [], fn {_, v} ->
               if is_map(v), do: v["population"], else: 0
             end)
           ) do
        {_, %{"color" => c}} -> c
        _ -> nil
      end

    prv = media["tiny_preview"]

    bcg =
      if col || prv,
        do: "background:#{col || ""} #{if prv, do: "url('#{prv}')", else: ""};",
        else: ""

    pad =
      if is_resp,
        do: "padding-bottom:#{media["height"] / media["width"] * 100}%",
        else: ""

    div(class: cls, style: "#{bcg}#{pad}", do: body)
  end

  def responsive_container(_, do: body), do: body

  def photo_rendered(photo) do
    use Taggart.HTML

    figure class: "entry-photo" do
      responsive_container(photo) do
        cond do
          is_bitstring(photo) ->
            img(class: "u-photo", src: photo, alt: "")

          is_map(photo) && photo["source"] ->
            srcs = as_many(photo["source"])

            default =
              srcs
              |> Stream.filter(&is_map/1)
              |> Enum.sort_by(fn x -> {x["default"] || false, x["type"] != "image/jpeg"} end)
              |> as_one

            content_tag :picture do
              taggart do
                srcs
                |> Stream.filter(fn src -> src != default && !src["original"] end)
                |> Enum.map(fn src ->
                  source(
                    srcset: src["srcset"] || src["src"],
                    media: src["media"],
                    sizes: src["sizes"],
                    type: src["type"]
                  )
                end)

                img(class: "u-photo", src: default["src"], alt: photo["alt"] || "")
              end
            end

          is_map(photo) && is_bitstring(photo["value"]) ->
            img(class: "u-photo", src: photo["value"], alt: photo["alt"] || "")

          true ->
            {:safe, "<!-- no img -->"}
        end
      end
    end
  end

  def inline_media_into_content(tree, props: props) do
    Markup.inline_media_into_content(
      tree,
      %{
        "photo" => &photo_rendered/1
      },
      %{
        "photo" => as_many(props["photo"]),
        "video" => as_many(props["video"]),
        "audio" => as_many(props["audio"])
      }
    )
  end

  def to_cite(url, preload: preload) when is_bitstring(url) do
    if preload[url] do
      preload[url] |> Doc.to_map() |> simplify
    else
      url
    end
  end

  def to_cite(entry = %Doc{}, preload: _), do: Doc.to_map(entry) |> simplify

  def to_cite(entry, preload: _) when is_map(entry), do: simplify(entry)

  def author(author, preload: _) when is_map(author) do
    use Taggart.HTML

    a href: author["url"], class: "u-author #{if author["name"], do: "h-card", else: ""}" do
      author["name"] || author["url"]
    end
  end

  def author(author, preload: preload) when is_bitstring(author) do
    if preload[author] do
      preload[author] |> Doc.to_map() |> simplify |> author(preload: preload)
    else
      author(%{"url" => author}, preload: preload)
    end
  end

  def home(preload) do
    preload["/"] ||
      %Doc{
        url: "/",
        props: %{"name" => "Create an entry at the root URL (/)!"}
      }
  end
end
