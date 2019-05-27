defmodule Sweetroll2.PostTest do
  use ExUnit.Case, async: true
  alias Sweetroll2.{Post, Post.Feed, Post.Comments}
  doctest Sweetroll2.Post

  describe "Feed.matches_filter?" do
    test "true when matches" do
      assert Feed.matches_filter?(%Post{props: %{"category" => "test", "x" => "y"}}, %{
               "category" => "test"
             })

      assert Feed.matches_filter?(%Post{props: %{"category" => "test", "x" => "y"}}, %{
               "category" => ["test"]
             })

      assert Feed.matches_filter?(%Post{props: %{"category" => ["test"], "x" => "y"}}, %{
               "category" => "test"
             })

      assert Feed.matches_filter?(%Post{props: %{"category" => ["test"], "x" => "y"}}, %{
               "category" => ["test"]
             })
    end

    test "false when doesn't match" do
      assert not Feed.matches_filter?(%Post{props: %{"category" => [], "x" => "y"}}, %{
               "category" => "test"
             })

      assert not Feed.matches_filter?(%Post{props: %{"category" => [], "x" => "y"}}, %{
               "category" => ["test"]
             })

      assert not Feed.matches_filter?(%Post{props: %{"x" => "y"}}, %{"category" => "test"})
      assert not Feed.matches_filter?(%Post{props: %{"x" => "y"}}, %{"category" => ["test"]})
    end
  end

  describe "Comments.separate_comments" do
    test "does not fail on no comments" do
      assert Comments.separate_comments(%Post{props: %{"comments" => []}}) == %{}
      assert Comments.separate_comments(%Post{props: %{"comments" => nil}}) == %{}
      assert Comments.separate_comments(%Post{}) == %{}
    end

    test "splits comments" do
      assert Comments.separate_comments(%Post{
               url: "/yo",
               props: %{
                 "comment" => [
                   %{"properties" => %{"x" => "like-str", "like-of" => "/yo"}},
                   %{properties: %{"x" => "like-atom", "like-of" => "/yo"}},
                   %{props: %{"x" => "like-atom-short", "like-of" => "/yo"}},
                   %{"x" => "like-direct", "like-of" => "/yo"},
                   %{"properties" => %{"x" => "reply-str", "in-reply-to" => "/yo"}},
                   %{properties: %{"x" => "repost-atom", "repost-of" => "/yo"}},
                   %{"properties" => %{"x" => "bookmark-str", "bookmark-of" => "/yo"}},
                   "whatever",
                   :lol,
                   nil,
                   69420
                 ]
               }
             }) == %{
               likes: [
                 %{"x" => "like-direct", "like-of" => "/yo"},
                 %{props: %{"x" => "like-atom-short", "like-of" => "/yo"}},
                 %{properties: %{"x" => "like-atom", "like-of" => "/yo"}},
                 %{"properties" => %{"x" => "like-str", "like-of" => "/yo"}}
               ],
               replies: [
                 %{"properties" => %{"x" => "reply-str", "in-reply-to" => "/yo"}}
               ],
               reposts: [
                 %{properties: %{"x" => "repost-atom", "repost-of" => "/yo"}}
               ],
               bookmarks: [
                 %{"properties" => %{"x" => "bookmark-str", "bookmark-of" => "/yo"}}
               ]
             }
    end
  end
end
