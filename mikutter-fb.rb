# -*- encoding: utf-8 -*-

require 'rubygems'
require 'koala'
require 'webrick'

Plugin.create :mikutter_fb do
  # アクセストークンを得る
  def get_access_token(*permissions)
    key = ""

    # OAuthリダイレクト先のWebサーバを起動する
    t = Thread.start {
      s = WEBrick::HTTPServer.new(:Port => 39012)

      s.mount_proc("/") { |req, res|
        key = req.query["code"].to_s
        res.body = "Facebookまでておくれさせるプラグイン\n認証が完了しました。ブラウザを閉じてください。"
        s.stop
      }

      s.start
    }

    # 認証開始
    access = Koala::Facebook::OAuth.new("554883974571348", "7d899c651e6793b9d1013d0f514c375b", "http://127.0.0.1:39012/")
    url = access.url_for_oauth_code(:permissions => permissions)
    Gtk::openurl(url)

    # コールバック先がアクセストークンを得るまで待つ
    if !t.join(60 * 2)
      return nil
    end

    # アクセストークンの期限を延ばす
    access.exchange_access_token_info(access.get_access_token(key))["access_token"]
  end

  # タブ
  tab :facebook, "Facebook" do
    set_icon "http://www.facebook.com/favicon.ico" 
    timeline :facebook
  end

  # 設定ウインドウ
  settings "Facebook" do
    closeup decide = ::Gtk::Button.new('アカウント認証')
    decide.signal_connect("clicked") {
      token = Plugin[:mikutter_fb].get_access_token("read_stream")

      if token
        UserConfig[:mikutter_fb_access_token] = token
      end

      Reserver.new(0) {
        main_loop
      }
    }
  end

  # statusメッセージ
  def create_status_message(feed)
    msg = nil

    if feed["message"]
      msg = feed["message"]
    end

    msg
  end

  # photo,videoメッセージ
  def create_photo_message(feed)
    msg = ""

    if feed["message"]
      msg = feed["message"]
    end

    if feed["link"]
      msg += "\n\n" + feed["link"]
    end

    if msg.length != 0
      msg
    else
      nil
    end
  end

  # linkメッセージ
  def create_link_message(feed)
    msg = ""

    if feed["message"]
      msg = feed["message"]
    end

    if feed["link"]
      msg += "\n\n" + feed["link"]
    end

    if msg.length != 0
      msg
    else
      nil
    end
  end

  # 一定周期でタイムラインを再描画する
  def main_loop()
    timeline(:facebook).clear

    user = Hash.new

    begin
      api = Koala::Facebook::API.new(UserConfig[:mikutter_fb_access_token])

      api.get_connection("me", "home", {:locale  =>  "ja_JP"}).each { |feed|
        msg = case feed["type"]
        when "status"
          create_status_message(feed)
        when "photo", "video"
          create_photo_message(feed)
        when "link"
          create_photo_message(feed)
        else
          nil
        end

        if !msg
          next
        end

        message = Message.new(:id => feed[:id], :message => "#{msg}" , :system => true)

        if !user[feed["from"]["id"]]
          user[feed["from"]["id"]] = api.get_object("#{feed["from"]["id"]}?fields=picture", {:locale  =>  "ja_JP"})["picture"]["data"]["url"]
        end

        message[:user] = User.new(:id => -3939,
                              :idname => "Facebook",
                              :name => feed["from"]["name"],
                              :profile_image_url => user[feed["from"]["id"]])

        message[:system] = false
	message[:created] = Time.parse(feed["created_time"])
	message[:modified] = Time.parse(feed["created_time"])
#	message[:modified] = Time.parse(feed["updated_time"])

        timeline(:facebook) << message
      }
    rescue => e
      message = Message.new(:message => "#{e}\n\nエラー。設定画面からアカウント認証をしてみよう" , :system => true)
      timeline(:facebook) << message
    end

    Reserver.new(60 * 600) {
      main_loop
    }
  end

  on_boot do |service|
    Reserver.new(0) {
      main_loop
    }
  end
end
