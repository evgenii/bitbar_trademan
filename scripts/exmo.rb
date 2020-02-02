require 'net/https'
require "json"

class Exmo
  attr_reader :currency_key, :options

  def initialize(currency_key, options = {})
    raise ArgumentError, "currency_key should be defined" if currency_key.nil?
    @currency_key = currency_key.is_a?(Array) ? currency_key : [currency_key]

    @options = options
  end

  def preform
    begin
      tikers = api_query(:tiker)
    rescue StandardError
      return {
        status: :connection_lost,
        itemImg: nil,
        itemText: "[!] Lost Coonection"
      }

    end

    currency_key.map do |key|
      tiker = tikers[key]

      return {
        status: :not_found,
        itemImg: nil,
        itemText: key + 'NOT FOUND',
      } unless tiker

      itemText = key
      description = []
      description += prepare_observe
      description += prepare_tiker(tiker)

      {
        status: :ok,
        itemImg: nil,
        itemText: itemText || key + 'NOT FOUND',
        itemHref: nil,

        title: nil,
        description: description
      }
    end
  end

  private

  def prepare_observe
    observe = opts(:observe)
    return [] if observe.nil? || observe.size.zero?

    ["Observers: "] + observe.map do |key, val|
      " -- #{key}: #{val}"
    end
  end

  def prepare_tiker(tiker)
    tiker.map{ |k, v|  "#{k}: #{v}" }
  end

  def api_query(action)
    uri = get_uri(action)
    req = Net::HTTP::Get.new(uri.path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    response = http.request(req)

    unless response.code == '200'
      raise StandardError.new(__method__), ['http error:', response.code].join(' ')
    end

    result = response.body.to_s

    unless result.is_a?(String) && valid_json?(result)
      raise StandardError.new(__method__), "Invalid json"
    end

    JSON.load(result)
  end


  def valid_json?(json)
    JSON.parse(json)
    true
  rescue
    false
  end


  def get_uri(action)
    uri_opts = public_requests[action]
    raise StandardError, "No Action found" if uri_opts.nil?

    URI.parse(uri_opts[:uri])
  end

  # see: https://exmo.com/uk/api#/public_api for more details
  def public_requests
    return @public_requests if defined?(@public_requests)

    @public_requests = {
      # Cтатистика цен и объемов торгов по валютным парам
      tiker: {
        uri: 'https://api.exmo.com/v1/ticker',
        method: :get
      },
      # Cписок валют биржи
      currency: {
        uri: 'https://api.exmo.com/v1/currency/',
        method: :get
      },
      # Настройки валютных пар
      pair_settings: {
        uri: 'https://api.exmo.com/v1/pair_settings/',
        method: :get
      },
      # Книга ордеров по валютной паре
      # Входящие параметры:
      #   - pair - одна или несколько валютных пар разделенных запятой (пример BTC_USD,BTC_EUR)
      #   - limit - кол-во отображаемых позиций (по умолчанию 100, максимум 1000)
      order_book: {
        uri: 'https://api.exmo.com/v1/order_book/?pair=BTC_USD',
        method: :get
      },
      # Список сделок по валютной паре
      # Входящие параметры:
      #   - pair - одна или несколько валютных пар разделенных запятой (пример BTC_USD,BTC_EUR)
      trades: {
        uri: 'https://api.exmo.com/v1/trades/?pair=BTC_USD',
        method: :get
      }
    }
  end

  def opts(key)
    options.dig(key.to_s)
  end
end
