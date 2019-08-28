defmodule Sweetroll2.Post.Generative do
  @moduledoc """
  Behaviour for post type processors that generate virtual sub-posts.
  """

  alias Sweetroll2.Post

  @type args :: %{atom => any}
  @type posts :: any
  @type local_urls :: any

  @callback apply_args(%Post{}, args, posts, local_urls) :: %Post{}
  @callback child_urls(%Post{}, posts, local_urls) :: %{String.t() => args}
  @callback parse_url_segment(%Post{}, String.t()) :: {String.t(), args} | :error

  def apply_args(%Post{type: "x-dynamic-feed"} = post, args, posts, local_urls),
    do: Post.Generative.Feed.apply_args(post, args, posts, local_urls)

  def apply_args(%Post{type: "x-dynamic-tag-feed"} = post, args, posts, local_urls),
    do: Post.Generative.Tag.apply_args(post, args, posts, local_urls)

  def apply_args(%Post{} = post, _, _, _), do: post

  def child_urls(%Post{type: "x-dynamic-feed"} = post, posts, local_urls),
    do: Post.Generative.Feed.child_urls(post, posts, local_urls)

  def child_urls(%Post{type: "x-dynamic-tag-feed"} = post, posts, local_urls),
    do: Post.Generative.Tag.child_urls(post, posts, local_urls)

  def child_urls(%Post{}, _, _), do: []

  def parse_url_segment(%Post{type: "x-dynamic-feed"} = post, seg),
    do: Post.Generative.Feed.parse_url_segment(post, seg)

  def parse_url_segment(%Post{type: "x-dynamic-tag-feed"} = post, seg),
    do: Post.Generative.Tag.parse_url_segment(post, seg)

  def parse_url_segment(%Post{}, _), do: :error

  @doc ~S"""
  Recursively expands a list of URLs to include sub-posts generated by generative posts.

      iex> Sweetroll2.Post.Generative.list_generated_urls(["/notes", "/tag", "/notes/dank-meme-7"], Map.merge(
      ...>  %{
      ...>    "/tag" => %Sweetroll2.Post{
      ...>      url: "/tag", type: "x-dynamic-tag-feed",
      ...>      props: %{ "filter" => [ %{"category" => ["{tag}"]} ] }
      ...>    },
      ...>    "/notes" => %Sweetroll2.Post{
      ...>      url: "/notes", type: "x-dynamic-feed",
      ...>      props: %{ "filter" => [ %{"category" => ["_notes"]} ] }
      ...>    },
      ...>  },
      ...>  Map.new(0..11, &{ "/notes/dank-meme-#{&1}",
      ...>    %Sweetroll2.Post{
      ...>      url: "/notes/dank-meme-#{&1}", type: "entry",
      ...>      props: %{ "category" => ["_notes", "memes"] ++ (if &1 < 5, do: ["dank"], else: []) }
      ...>    }
      ...> })), ["/notes" | ["/tag" | Enum.map(0..11, &"/notes/dank-meme-#{&1}")]])
      ["/notes", "/notes/page1", "/tag", "/tag/dank", "/tag/memes", "/tag/memes/page1", "/notes/dank-meme-7"]
  """
  def list_generated_urls(urls, posts, local_urls) do
    Enum.flat_map(urls, fn url ->
      [url | child_urls_rec(posts[url], posts, local_urls)]
    end)
  end

  def child_urls_rec(post, posts, local_urls) do
    child_urls(post, posts, local_urls)
    |> Enum.flat_map(fn {url, args} ->
      [url | child_urls_rec(apply_args(post, args, posts, local_urls), posts, local_urls)]
    end)
    |> Enum.uniq()
  end

  @doc ~S"""
  Looks up a post in posts, even if it's a sub-post generated by (a chain of) generative posts.

      iex> post = Sweetroll2.Post.Generative.lookup("/tag/memes/page1", Map.merge(
      ...>  %{
      ...>    "/tag" => %Sweetroll2.Post{
      ...>      url: "/tag", type: "x-dynamic-tag-feed",
      ...>      props: %{ "filter" => [ %{"category" => ["{tag}"]} ] }
      ...>    },
      ...>  },
      ...>  Map.new(0..11, &{ "/notes/dank-meme-#{&1}",
      ...>    %Sweetroll2.Post{
      ...>      url: "/notes/dank-meme-#{&1}", type: "entry",
      ...>      props: %{ "category" => ["dank", "memes"] }
      ...>    }
      ...> })), ["/tag" | Enum.map(0..11, &"/notes/dank-meme-#{&1}")])
      iex> post.children == ["/notes/dank-meme-10", "/notes/dank-meme-11"]
      true
      iex> post.url == "/tag/memes/page1"
      true
      iex> post.type == "feed"
      true

      iex> post = Sweetroll2.Post.Generative.lookup("/tag",
      ...>  %{
      ...>    "/tag" => %Sweetroll2.Post{
      ...>      url: "/tag", type: "x-dynamic-tag-feed",
      ...>      props: %{ "filter" => [ %{"category" => ["{tag}"]} ] }
      ...>    },
      ...>  }, ["/tag"])
      iex> post.type == "feed"
      true

      iex> post = Sweetroll2.Post.Generative.lookup("/",
      ...>  %{
      ...>    "/" => %Sweetroll2.Post{
      ...>      url: "/", type: "entry",
      ...>    },
      ...>  }, ["/"])
      iex> post.type == "entry"
      true
  """
  def lookup(url, posts, local_urls) do
    {generator, suffix} =
      if url == "/",
        do: {posts["/"], ""},
        else: find_first_matching_prefix(String.split(url, "/", trim: true), [], posts)

    generator && lookup_rec(generator, suffix, posts, local_urls)
  end

  defp lookup_rec(%Post{type: type} = post, "", _, _)
       when type != "x-dynamic-feed" and type != "x-dynamic-tag-feed",
       do: post

  defp lookup_rec(%Post{type: type}, _, _, _)
       when type != "x-dynamic-feed" and type != "x-dynamic-tag-feed",
       do: nil

  defp lookup_rec(%Post{} = generator, url_suffix, posts, local_urls) do
    case parse_url_segment(generator, url_suffix) do
      :error ->
        nil

      {next_suffix, args} ->
        apply_args(generator, args, posts, local_urls)
        |> lookup_rec(next_suffix, posts, local_urls)
    end
  end

  @doc """
  Finds the generative post probably responsible for the URL.
  (First argument is split parts of the URL, second is for recursion.)

      iex> Sweetroll2.Post.Generative.find_first_matching_prefix([""], [], %{"/" => 1})
      {1, ""}

      iex> Sweetroll2.Post.Generative.find_first_matching_prefix(["page1"], [], %{"/" => 1})
      {1, "/page1"}

      iex> Sweetroll2.Post.Generative.find_first_matching_prefix(["one"], [], %{"/one" => 1})
      {1, ""}

      iex> Sweetroll2.Post.Generative.find_first_matching_prefix(["one", "page2"], [], %{"/one" => 1})
      {1, "/page2"}

      iex> Sweetroll2.Post.Generative.find_first_matching_prefix(["tag", "memes", "page69"], [], %{"/tag" => :tagpage})
      {:tagpage, "/memes/page69"}

      iex> Sweetroll2.Post.Generative.find_first_matching_prefix(["memes", "page69"], [], %{"/tag" => :tagpage})
      nil
  """
  def find_first_matching_prefix(l, r, posts) do
    if post = posts["/#{Enum.join(l, "/")}"] do
      r_path = if Enum.empty?(r), do: "", else: "/" <> Enum.join(r, "/")
      {post, r_path}
    else
      case Enum.split(l, -1) do
        {ll, [rr]} -> find_first_matching_prefix(ll, [rr | r], posts)
        _ -> nil
      end
    end
  end
end
