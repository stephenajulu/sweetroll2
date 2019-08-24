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
  alias Sweetroll2.{Post, Markup}
  import Sweetroll2.{Convert, Render.Tpl}
  import Phoenix.HTML.Tag
  import Phoenix.HTML
  require Logger
  require EEx

  deftpl :head, "tpl/head.html.eex"
  deftpl :header, "tpl/header.html.eex"
  deftpl :footer, "tpl/footer.html.eex"
  deftpl :entry, "tpl/entry.html.eex"
  deftpl :cite, "tpl/cite.html.eex"
  deftpl :page_entry, "tpl/page_entry.html.eex"
  deftpl :page_feed, "tpl/page_feed.html.eex"
  deftpl :page_login, "tpl/page_login.html.eex"
  deftpl :page_authorize, "tpl/page_authorize.html.eex"

  @doc """
  Renders a post, choosing the right template based on its type.

  - `post`: current post
  - `posts`: `Access` object for retrieval of posts by URL
  - `local_urls`: Enumerable of at least local URLs -- all URLs are fine, will be filtered anyway
  - `logged_in`: bool
  """
  def render_post(
        post: post = %Post{},
        params: params,
        posts: posts,
        local_urls: local_urls,
        logged_in: logged_in
      ) do
    feed_urls = Post.filter_type(local_urls, posts, ["x-dynamic-feed", "x-dynamic-tag-feed"])

    cond do
      post.type == "entry" || post.type == "review" ->
        post = Post.Comments.inline_comments(post, posts)
        page_entry(entry: post, posts: posts, feed_urls: feed_urls, logged_in: logged_in)

      post.type == "x-custom-page" ->
        {:ok, html, _} =
          Post.Page.get_template(post)
          |> Post.Page.render(%{
            "canonical_home_url" => Sweetroll2.canonical_home_url(),
            page: post,
            posts: posts,
            logged_in: logged_in,
            local_urls: local_urls,
            feed_urls: feed_urls
          })

        {:safe, html}

      post.type == "x-dynamic-feed" || post.type == "x-dynamic-tag-feed" ||
          post.type == "x-inbox-feed" ->
        page = params[:page] || 0

        post = if params[:tag], do: Post.Tags.subst_tag(post, params[:tag]), else: post

        children =
          Post.Feed.filter_feed_entries(post, posts, local_urls)
          |> Post.Feed.sort_feed_entries(posts)

        page_children =
          Enum.slice(children, page * 10, 10)
          |> Enum.map(&Post.Comments.inline_comments(&1, posts))

        page_feed(
          feed: %{post | children: page_children},
          posts: posts,
          feed_urls: feed_urls,
          per_page: 10,
          page_count: Post.Feed.feed_page_count(children),
          cur_page: page,
          logged_in: logged_in
        )

      true ->
        {:error, :unknown_type, post.type}
    end
  end

  defmacro tif(expr, do: block) do
    quote do
      if unquote(expr) do
        taggart do
          unquote(block)
        end
      else
        []
      end
    end
  end

  # for returning one thing inside taggart
  # but with local vars
  defmacro t1if(expr, do: block) do
    quote do
      if unquote(expr) do
        unquote(block)
      else
        []
      end
    end
  end

  @asset_dir "priv/static"

  def asset(url) do
    "/__as__/#{url}?vsn=#{
      ConCache.get_or_store(:asset_rev, url, fn ->
        :crypto.hash(:sha256, File.read!(Path.join(@asset_dir, url)))
        |> Base.url_encode64()
        |> String.slice(0, 24)
      end)
    }"
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

  def readable_datetime!(dt), do: Timex.format!(dt, "{Mshort} {D}, {YYYY} {h24}:{m}")

  def time_permalink(%Post{published: published, url: url}, rel: rel) do
    use Taggart.HTML

    attrdt = if published, do: DateTime.to_iso8601(published), else: ""

    readabledt = if published, do: readable_datetime!(published), else: "<permalink>"

    time datetime: attrdt, class: "dt-published" do
      a href: url, class: "u-url u-uid", rel: rel do
        readabledt
      end
    end
  end

  def time_permalink_cite(%{} = cite) do
    use Taggart.HTML

    dt =
      if is_bitstring(cite["published"]) do
        DateTimeParser.parse_datetime(cite["published"], assume_utc: true)
      else
        {:error, "weird non-string date"}
      end

    attrdt =
      case dt do
        {:ok, d} -> DateTime.to_iso8601(d)
        _ -> ""
      end

    readabledt =
      case dt do
        {:ok, d} -> readable_datetime!(d)
        _ -> "<permalink>"
      end

    time datetime: attrdt, class: "dt-published" do
      a href: filter_scheme(as_one(cite["url"])), class: "u-url u-uid" do
        readabledt
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

  def post_title(post) do
    post.props["name"] || DateTime.to_iso8601(post.published)
  end

  def responsive_container(media, do: body) when is_map(media) do
    use Taggart.HTML

    is_resp = is_integer(media["width"]) && is_integer(media["height"])

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

    content_tag(
      :"responsive-container",
      [class: if(is_resp, do: "has-pad", else: nil), style: "#{bcg}#{pad}"],
      do: body
    )
  end

  def responsive_container(_, do: body), do: content_tag(:"responsive-container", [], do: body)

  defp parse_ratio(s) when is_bitstring(s) do
    case String.split(s, "/") do
      [x, y] ->
        case {Integer.parse(x), Integer.parse(y)} do
          {{x, _}, {y, _}} ->
            [x, y]

          _ ->
            Logger.warn("could not parse ratio '#{s}'", event: %{ratio_parse_failed: %{string: s}})

            [0, 1]
        end

      _ ->
        Logger.warn("could not parse ratio '#{s}'", event: %{ratio_parse_failed: %{string: s}})
        [0, 1]
    end
  end

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

      t1if is_map(photo) && photo["meta"] do
        meta = photo["meta"]
        make = meta["Exif.Image.Make"]

        model =
          if meta["Exif.Image.Model"],
            do: meta["Exif.Image.Model"] |> String.replace(make, "") |> String.trim(),
            else: nil

        lens = meta["Exif.Canon.LensModel"] || meta["Exif.Photo.LensModel"]
        lens_make = meta["Exif.Canon.LensMake"] || meta["Exif.Photo.LensMake"]

        lens_model =
          if lens && lens_make,
            do: lens |> String.replace(lens_make, "") |> String.trim(),
            else: lens

        aperture = meta["Exif.Image.FNumber"] || meta["Exif.Photo.FNumber"]
        shutter = meta["Exif.Image.ExposureTime"] || meta["Exif.Photo.ExposureTime"]
        iso = meta["Exif.Photo.ISOSpeedRatings"] || meta["Exif.Photo.ISOSpeed"]
        software = meta["Exif.Image.Software"]
        original = as_many(photo["source"]) |> Enum.find(& &1["original"])

        t1if make || model || lens || aperture || shutter || iso || software || original do
          figcaption class: "entry-photo-meta" do
            tif make || model do
              icon(name: "device-camera", title: "Camera")
              t1if(make, do: span(class: "camera-make", do: make))
              t1if(model, do: span(class: "camera-model", do: model))
            end

            tif lens_model do
              icon(name: "telescope", title: "Lens")
              t1if(lens_make, do: span(class: "lens-make", do: lens_make))
              t1if(lens_model, do: span(class: "lens-model", do: lens_model))
            end

            tif aperture || shutter || iso do
              icon(name: "eye", title: "Photo parameters")

              t1if shutter do
                [x, y] = parse_ratio(shutter)

                span(
                  class: "camera-shutter",
                  do: if(x / y >= 0.3, do: "#{Float.round(x / y, 2)}s", else: shutter)
                )
              end

              t1if aperture do
                [x, y] = parse_ratio(aperture)
                span(class: "camera-aperture", do: "ƒ/#{Float.round(x / y, 2)}")
              end

              t1if iso do
                span(class: "camera-iso", do: "ISO #{iso}")
              end
            end

            tif software do
              icon(name: "paintcan", title: "Editing software")
              span(class: "camera-software", do: software)
            end

            tif original do
              icon(name: "desktop-download")
              a(class: "camera-original", href: original["src"], do: "Download original")
            end
          end
        end
      end
    end
  end

  def video_rendered(video) do
    use Taggart.HTML

    figure class: "entry-video" do
      responsive_container(video) do
        cond do
          is_bitstring(video) ->
            video(class: "u-video", src: video)

          is_map(video) && video["source"] ->
            srcs = as_many(video["source"])
            poster = srcs |> Enum.find(&String.starts_with?(&1["type"], "image"))

            video class: "u-video",
                  poster: poster["src"],
                  controls: video["controls"] || true,
                  autoplay: video["autoplay"] || false,
                  loop: video["loop"] || false,
                  muted: video["muted"] || false,
                  playsinline: video["playsinline"] || false,
                  width: video["width"],
                  height: video["height"] do
              for src <- Enum.filter(srcs, &(!String.starts_with?(&1["type"], "image"))) do
                source(src: src["src"], type: src["type"])
              end

              for track <- as_many(video["track"]) do
                track(
                  src: track["src"],
                  kind: track["kind"],
                  label: track["label"],
                  srclang: track["srclang"],
                  default: track["default"] || false
                )
              end
            end

          is_map(video) && is_bitstring(video["value"]) ->
            video(class: "u-video", src: video["value"])

          true ->
            {:safe, "<!-- no video -->"}
        end
      end
    end
  end

  def audio_rendered(audio) do
    use Taggart.HTML

    audio class: "u-audio entry-audio",
          controls: audio["controls"] || true,
          autoplay: audio["autoplay"] || false,
          loop: audio["loop"] || false,
          muted: audio["muted"] || false do
      tif is_list(audio["source"]) or is_binary(audio["source"]) do
        for src <- as_many(audio["source"]) do
          source(src: src["src"], type: src["type"])
        end
      end

      t1if is_binary(audio["value"]) do
        source(src: audio["value"])
      end
    end
  end

  def inline_media_into_content(tree, props: props) do
    Markup.inline_media_into_content(
      tree,
      %{
        "photo" => &photo_rendered/1,
        "video" => &video_rendered/1,
        "audio" => &audio_rendered/1
      },
      %{
        "photo" => as_many(props["photo"]),
        "video" => as_many(props["video"]),
        "audio" => as_many(props["audio"])
      }
    )
  end

  def to_cite(url, posts: posts) when is_bitstring(url) do
    if posts[url] do
      posts[url] |> Post.to_map() |> simplify
    else
      url
    end
  end

  def to_cite(%Post{} = entry, posts: _), do: Post.to_map(entry) |> simplify

  def to_cite(entry, posts: _) when is_map(entry), do: simplify(entry)

  def author(author, posts: _) when is_map(author) do
    use Taggart.HTML

    a href: filter_scheme(author["url"]),
      class: "u-author #{if author["name"], do: "h-card", else: ""}" do
      author["name"] || author["url"] || "<unknown author>"
    end
  end

  def author(author, posts: posts) when is_bitstring(author) do
    if posts[author] do
      posts[author] |> Post.to_map() |> simplify |> author(posts: posts)
    else
      author(%{"url" => author}, posts: posts)
    end
  end

  def home(posts) do
    posts["/"] ||
      %Post{
        url: "/",
        props: %{"name" => "Create an entry at the root URL (/)!"}
      }
  end

  def feed_urls_filter(feed_urls, posts: posts, show_prop: show_prop, order_prop: order_prop) do
    feed_urls
    |> Stream.filter(fn url ->
      try do
        Access.get(as_one(posts[url].props["feed-settings"]), show_prop, true)
      rescue
        _ -> true
      end
    end)
    |> Enum.sort_by(fn url ->
      try do
        Access.get(as_one(posts[url].props["feed-settings"]), order_prop, 1)
      rescue
        _ -> 1
      end
    end)
  end

  def filter_scheme("http://" <> _ = x), do: x
  def filter_scheme("https://" <> _ = x), do: x
  def filter_scheme(_), do: "#non_http_url_found"
end

defmodule Sweetroll2.Render.LiquidTags.Head do
  alias Sweetroll2.Render

  def parse(%Liquid.Tag{} = tag, %Liquid.Template{} = context) do
    {tag, context}
  end

  def render(output, tag, context) do
    {:safe, data} = Render.head(title: tag.markup, cur_url: context.assigns.page.url)
    {[IO.iodata_to_binary(data)] ++ output, context}
  end
end

defmodule Sweetroll2.Render.LiquidTags.Header do
  alias Sweetroll2.Render

  def parse(%Liquid.Tag{} = tag, %Liquid.Template{} = context) do
    {tag, context}
  end

  def render(output, _tag, context) do
    {:safe, data} =
      Render.header(
        posts: context.assigns.posts,
        cur_url: context.assigns.page.url,
        feed_urls: context.assigns.feed_urls
      )

    {[IO.iodata_to_binary(data)] ++ output, context}
  end
end

defmodule Sweetroll2.Render.LiquidTags.Footer do
  alias Sweetroll2.Render

  def parse(%Liquid.Tag{} = tag, %Liquid.Template{} = context) do
    {tag, context}
  end

  def render(output, _tag, context) do
    {:safe, data} = Render.footer(logged_in: context.assigns.logged_in)
    {[IO.iodata_to_binary(data)] ++ output, context}
  end
end

defmodule Sweetroll2.Render.LiquidTags.FeedPreview do
  alias Sweetroll2.{Render, Post}

  def parse(%Liquid.Tag{} = tag, %Liquid.Template{} = context) do
    {tag, context}
  end

  def render(output, tag, context) do
    feed = context.assigns.posts[tag.markup]

    children =
      Post.Feed.filter_feed_entries(feed, context.assigns.posts, context.assigns.local_urls)
      |> Post.Feed.sort_feed_entries(context.assigns.posts)
      |> Enum.slice(0, 5)
      |> Enum.map(&Post.Comments.inline_comments(&1, context.assigns.posts))

    # TODO: adjustable number

    {Enum.map(children, fn entry ->
       {:safe, data} =
         Render.entry(
           posts: context.assigns.posts,
           cur_url: context.assigns.page.url,
           logged_in: context.assigns.logged_in,
           entry: entry,
           feed_urls: context.assigns.feed_urls,
           expand_comments: false
         )

       IO.iodata_to_binary([~S[<article class="h-entry">], data, "</article>"])
     end) ++ output, context}
  end
end
