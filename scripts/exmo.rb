require 'net/https'
require "json"

class Exmo
  DEFAULT_STEP = 5 # ~5%
  attr_reader :currency_key, :options

  #
  # @param currency_key [String]
  # @param options = {} [Hash] [description]
  #   @option step [Integer, Float] options [default: DEFAULT_STEP]
  #   @option observe [Hash] options
  #     @option identity [Hash] observe
  #       @option buy [Integer, Float] identity
  #       @option sell [Integer, Float] identity
  #
  #  @example:
  #    "options": {
  #      "step": 0.02,
  #      "observe": {
  #        "1.01.20": {
  #          "buy": 9300
  #        }
  #      }
  #    }
  #
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

      description = []
      description += prepare_observe(tiker)
      description += prepare_tiker(tiker)

      itemText = key
      status = :ok

      observe_state = prepare_observe_state(tiker).round(3)
      step = opts(:step) || DEFAULT_STEP
      if observe_state > 0.01 && observe_state > step
        itemText = '↑ ' + itemText
        status = :grow
      elsif observe_state < -0.01 && observe_state < -step
        itemText = '↓ ' + itemText
        status = :fall
      end

      {
        status: status,
        itemImg: nil,
        itemText: itemText,
        itemHref: "https://exmo.com/uk/trade/#{key}",

        title: nil,
        description: description
      }
    end
  end

  private

  def prepare_observe(tiker)
    observe = opts(:observe)
    return [] if observe.nil? || observe.size.zero?
    step = opts(:step) || DEFAULT_STEP # step from user options or 5%

    ["Observers: "] + observe.map do |identy, order|
      state = '[|]'
      order_type, order_val = order.to_a[0]
      # ↑↓⇡⇞⇣⇟
      prcent = calc_prcent(order_type, order_val, tiker)
      rnd = prcent.round(3).abs
      state = "[#{prcent > 0.01 ? '↑' : '↓'}#{rnd}]"
      color = "| color=#{prcent > 0.01 ? 'green' : 'red'}" if rnd > step

      " -- #{state} #{identy} #{order_type}: #{order_val} #{color}"
    end
  end

  def prepare_observe_state(tiker)
    observe = opts(:observe)
    return 0 if observe.nil? || observe.size.zero?

    observe.map do |_, order|
      order_type, order_val = order.to_a[0]
      calc_prcent(order_type, order_val, tiker)
    end.reduce(0, :+)
  end

  def calc_prcent(order_type, order_val, tiker)
    if order_type == 'buy'
      price = tiker['sell_price'].to_f

      (price - order_val) / price * 100
    elsif order_type == 'sell'
      price = tiker['buy_price'].to_f

      (order_val - price) / order_val * 100
    else
      raise ArgumentError, "Wrong type argument, can be only buy or sell!"
    end
  end

  def prepare_tiker(tiker)
    ignore_keys = %w[vol vol_curr]
    ["Tikers: "] + tiker.map do |k, v|
      next if ignore_keys.include?(k)

      v = Time.at(v) if k == 'updated'

      "-- #{k}: #{v}"
    end.compact
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
