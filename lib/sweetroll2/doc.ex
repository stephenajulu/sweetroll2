defmodule Sweetroll2.Doc do
  use Ecto.Schema
  import Ecto.Changeset
  require Logger
  alias Sweetroll2.{Convert}

  @primary_key {:url, :string, []}

  schema "docs" do
    field :type, :string
    field :deleted, :boolean
    field :published, :utc_datetime
    field :updated, :utc_datetime
    field :acl, {:array, :string}
    field :props, :map
    field :children, {:array, :map}
  end

  @real_fields [:url, :type, :deleted, :published, :updated, :acl, :children]

  def atomize_real_key({"url", v}), do: {:url, v}
  def atomize_real_key({"type", v}), do: {:type, v}
  def atomize_real_key({"deleted", v}), do: {:deleted, v}
  def atomize_real_key({"published", v}), do: {:published, v}
  def atomize_real_key({"updated", v}), do: {:updated, v}
  def atomize_real_key({"acl", v}), do: {:acl, v}
  def atomize_real_key({"children", v}), do: {:children, v}
  def atomize_real_key({k, v}), do: {k, v}

  def changeset(struct, params) do
    {allowed, others} = params |> Map.new(&atomize_real_key/1) |> Map.split(@real_fields)
    params = Map.put(allowed, :props, others)

    struct
    |> cast(params, [:props | @real_fields])
    |> validate_required([:url, :type, :published])
  end

  def to_map(%__MODULE__{
        props: props,
        url: url,
        type: type,
        deleted: deleted,
        published: published,
        updated: updated,
        acl: acl,
        children: children
      }) do
    props
    |> Map.put("url", url)
    |> Map.put("type", type)
    |> Map.put("deleted", deleted)
    |> Map.put("published", published)
    |> Map.put("updated", updated)
    |> Map.put("acl", acl)
    |> Map.put("children", children)
  end

  def to_map(x) when is_map(x), do: x

  def matches_filter?(doc = %__MODULE__{}, filter) do
    Enum.all?(filter, fn {k, v} ->
      docv = Convert.as_many(doc.props[k])
      Enum.all?(Convert.as_many(v), &Enum.member?(docv, &1))
    end)
  end

  def matches_filters?(doc = %__MODULE__{}, filters) do
    Enum.any?(filters, &matches_filter?(doc, &1))
  end

  def in_feed?(doc = %__MODULE__{}, feed = %__MODULE__{}) do
    matches_filters?(doc, Convert.as_many(feed.props["filter"])) and
      not matches_filters?(doc, Convert.as_many(feed.props["unfilter"]))
  end

  def filter_feeds(urls, preload) do
    Stream.filter(urls, fn url ->
      String.starts_with?(url, "/") && preload[url] && preload[url].type == "x-dynamic-feed"
    end)
  end

  def filter_feed_entries(doc = %__MODULE__{type: "x-dynamic-feed"}, preload, allu) do
    Stream.filter(allu, &(String.starts_with?(&1, "/") and in_feed?(preload[&1], doc)))
    |> Enum.sort(&(DateTime.compare(preload[&1].published, preload[&2].published) == :gt))

    # TODO rely on sorting from repo (should be sorted in Generate too)
  end

  def feed_page_count(entries) do
    # TODO get per_page from feed settings
    ceil(Enum.count(entries) / Application.get_env(:sweetroll2, :entries_per_page, 10))
  end

  def page_url(url, 0), do: url
  def page_url(url, page), do: String.replace_leading("#{url}/page#{page}", "//", "/")

  def dynamic_urls_for(doc = %__MODULE__{type: "x-dynamic-feed"}, preload, allu) do
    cnt = feed_page_count(filter_feed_entries(doc, preload, allu))
    Map.new(1..cnt, &{page_url(doc.url, &1), {doc.url, %{page: &1}}})
  end

  # TODO def dynamic_urls_for(doc = %__MODULE__{type: "x-dynamic-tag-feed"}, preload, allu) do end

  def dynamic_urls_for(_, _, _), do: %{}

  def dynamic_urls(preload, allu) do
    Stream.map(allu, &dynamic_urls_for(preload[&1], preload, allu))
    |> Enum.reduce(&Map.merge/2)
  end

  defp lookup_property(%__MODULE__{props: props}, prop), do: props[prop]

  defp lookup_property(x, prop) when is_map(x) do
    x[prop] || x["properties"][prop] || x[:properties][prop] || x["props"][prop] ||
      x[:props][prop]
  end

  defp lookup_property(_, _), do: false

  defp compare_property(x, prop, url) when is_bitstring(prop) and is_bitstring(url) do
    lookup_property(x, prop)
    |> Convert.as_many()
    |> Enum.any?(fn val ->
      url && val &&
        (val == url || URI.parse(val) == URI.merge(Sweetroll2.our_host(), URI.parse(url)))
    end)
  end

  def inline_comments(doc = %__MODULE__{url: url, props: props}, preload) do
    Logger.debug("inline comments: working on #{url}")

    comments =
      props["comment"]
      |> Convert.as_many()
      |> Enum.map(fn
        u when is_bitstring(u) ->
          Logger.debug("inline comments: inlining #{u}")
          preload[u]

        x ->
          x
      end)

    Map.put(doc, :props, Map.put(props, "comment", comments))
  end

  def inline_comments(doc_url, preload) when is_bitstring(doc_url) do
    Logger.debug("inline comments: loading #{doc_url}")
    res = preload[doc_url]
    if res != doc_url, do: inline_comments(res, preload), else: res
  end

  def inline_comments(x, _), do: x

  @doc """
  Splits "comments" (saved webmentions) by post type.

  Requires entries to be maps (does not load urls from the database).

  Lists are reversed.
  """
  def separate_comments(doc = %__MODULE__{url: url, props: %{"comment" => comments}})
      when is_list(comments) do
    Enum.reduce(comments, %{}, fn x, acc ->
      cond do
        # TODO reacji
        compare_property(x, "in-reply-to", url) -> Map.update(acc, :replies, [x], &[x | &1])
        compare_property(x, "like-of", url) -> Map.update(acc, :likes, [x], &[x | &1])
        compare_property(x, "repost-of", url) -> Map.update(acc, :reposts, [x], &[x | &1])
        compare_property(x, "bookmark-of", url) -> Map.update(acc, :bookmarks, [x], &[x | &1])
        compare_property(x, "quotation-of", url) -> Map.update(acc, :quotations, [x], &[x | &1])
        true -> acc
      end
    end)
  end

  def separate_comments(doc = %__MODULE__{}), do: %{}
end
