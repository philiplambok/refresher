# frozen_string_literal: true

class TwitterRefresher
  include Sidekiq::Worker
  sidekiq_options queue: :twitter_refresher, retry: false

  def perform(feed_id, feed_url, keys)
    feed = nil

    recognized_url = Feedkit::TwitterURLRecognizer.new(feed_url, nil)

    if recognized_url.valid?
      keys.find do |key|
        feed = Feedkit::Tweets.new(recognized_url, key["twitter_access_token"], key["twitter_access_secret"]).feed
      rescue Twitter::Error::Unauthorized
      end
    end

    if feed
      entries = EntryFilter.filter!(feed.entries, check_for_updates: false)
      unless entries.empty?
        Sidekiq::Client.push(
          "class" => "FeedRefresherReceiver",
          "queue" => "feed_refresher_receiver",
          "args" => [{
            feed: {
              id: feed_id,
              options: feed.options
            },
            entries: entries
          }],
        )
      end
    end
  end
end

class TwitterRefresherCritical
  include Sidekiq::Worker
  sidekiq_options queue: :twitter_refresher_critical, retry: false
  def perform(*args)
    TwitterRefresher.new.perform(*args)
  end
end
