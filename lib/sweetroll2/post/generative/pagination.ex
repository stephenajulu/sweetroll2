defmodule Sweetroll2.Post.Generative.Pagination do
  @moduledoc """
  Post type processor for `x-paginated-feed`.

  Mainly intended for use by other feeds, but if you wanted to paginate a manually curated feed, you could.
  """

  require Logger
  alias Sweetroll2.{Convert, Post, Post.Generative}

  @behaviour Generative

  def page_url(url, 0), do: url
  def page_url(url, page), do: String.replace_leading("#{url}/page#{page}", "//", "/")

  def per_page(%Post{props: props}) do
    Convert.as_one(props["pagination-settings"])["per-page"] || 10
  end

  @impl true
  def apply_args(
        %Post{type: "x-paginated-feed", url: url, props: props, children: children} = post,
        %{page: page},
        _,
        _
      ) do
    pp = per_page(post)

    %{
      post
      | url: page_url(url, page),
        type: "feed",
        children: Enum.slice(children, page * pp, pp),
        props:
          props
          |> Map.put("x-feed-base-url", url)
          |> Map.put("x-cur-page", page)
          |> Map.put("x-page-count", ceil(Enum.count(children) / per_page(post)))
    }
  end

  @impl true
  def child_urls(%Post{type: "x-paginated-feed", url: url, children: children} = post, _, _) do
    cnt = ceil(Enum.count(children) / per_page(post))

    if cnt < 2, do: %{}, else: Map.new(1..(cnt - 1), &{page_url(url, &1), %{page: &1}})
  end

  @impl true
  @doc """
      iex> Pagination.parse_url_segment(nil, "/page123")
      {"", %{page: 123}}

      iex> Pagination.parse_url_segment(nil, "/page1/what")
      {"/what", %{page: 1}}
  """
  def parse_url_segment(_, ""), do: {"", %{page: 0}}

  def parse_url_segment(_, "/page" <> n) do
    case Integer.parse(n) do
      {n, rest} -> {rest, %{page: n}}
      :error -> :error
    end
  end

  def parse_url_segment(_, _), do: :error
end
