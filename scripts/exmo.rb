require 'net/https'
require "json"

class Exmo
  DEFAULT_STEP = 2 # ~2%
  # ↑↓⇡⇣⇞⇟
  UP_SYMBOL = '↑'.freeze
  DOWN_SYMBOL = '↓'.freeze
  SYMBOLS_MAP = {
    'BTC' => 'B',
    'USD' => '$',
    'USDT' => '$'
  }

  attr_reader :currency_keys, :options

  #
  # @param options = {} [Hash] [description]
  #   @option step [Integer, Float] options [default: DEFAULT_STEP]
  #   @option observe [Hash] options
  #     @option currenty [Array] observe
  #       @option identity [Hash] currenty
  #         @option buy [Integer, Float] identity
  #         @option sell [Integer, Float] identity
  #
  #  @example:
  #    "options": {
  #      "step": 0.02,
  #      "observe": {
  #        "BTC_USD": [
  #          {"0.01 BTC": { "buy": 9300 }}
  #        ],
  #        "BTC_EUR": [
  #          {"Text": { "buy": 8300 }}
  #        ]
  #      },
  #      "hotkeys": {
  #        "BUY 0.0001 BTC": {
  #          "action": "market_buy",
  #          "currency": "BTC_USD",
  #          "value": 0.0001
  #        }
  #      },
  #      "credentials": {
  #        "key": "__EXMO_KEY_HERE__",
  #        "secret": "__EXMO_SECRET_HERE__"
  #      }
  #    }
  #
  def initialize(options = {})
    @options = options
  end

  def preform
    begin
      tickers = api_query(:ticker)
    rescue StandardError
      return {
        status: :connection_lost,
        itemImg: nil,
        itemText: "[!] Lost Coonection"
      }

    end
    currency_keys = opts(:observe).keys
    currency_keys.each_with_index.map do |currency_key, idx|
      ticker = tickers[currency_key]

      return {
        status: :not_found,
        itemImg: nil,
        itemText: currency_key + 'NOT FOUND',
      } unless ticker

      description = []
      description += prepare_observe(currency_key, ticker)
      description += prepare_ticker(ticker)
      description += prepare_history(currency_key)

      itemText = currency_key
      status = :ok
      on_top = false

      last_trade = ticker['last_trade'].to_f
      observe_state = prepare_observe_state(currency_key, ticker)
      unless observe_state.nil?
        observe_state = observe_state.round(3)
        step = opts(:step) || DEFAULT_STEP
        if observe_state > 0.01
          itemText = "#{UP_SYMBOL}[#{observe_state}] #{itemText}"
          high_price = ticker['high'].to_f;
          on_top = true if (high_price - high_price * 0.005) < last_trade
          status = :grow if observe_state > step
        elsif observe_state < -0.01
          itemText = "#{DOWN_SYMBOL}[#{observe_state}] #{itemText}"
          low_price = ticker['low'].to_f
          on_top = true if (low_price + low_price * 0.005) > last_trade
          status = :fall if observe_state < -step
        end
      end

      res = {
        on_top: on_top,
        status: status,
        value: observe_state,
        symbol: get_symbol(currency_key),
        last_trade: last_trade,

        itemImg: nil,
        itemText: itemText,
        itemHref: "https://exmo.com/uk/trade/#{currency_key}",

        title: nil,
        description: description
      }
      res[:hotkeys] = build_hotkeys if idx.zero?
      res
    end
  end

  private

  def build_hotkeys
    hotkeys = opts(:hotkeys)
    credentials = opts(:credentials)
    return {} if hotkeys.nil? || hotkeys.empty?
    return {} if credentials.nil? || credentials.empty?

    creds = "--credential_key=#{credentials['key']} --credential_secret=#{credentials['secret']}"
    script_path = File.expand_path('./', __FILE__)

    result = hotkeys.each_with_object({}) do |(name, params), memo|
      if params['cmd']
        command = params['cmd']
        command.gsub!('__FILE_DIR__', File.expand_path('../', __FILE__))

        memo[name] = command
      elsif params['action'] && params['value']
        currency = "--currency=#{params['currency']}"
        action = "--action=#{params['action']}"
        value = "--value=#{params['value']}"

        memo[name] = "ruby #{script_path} #{action} #{currency} #{value} #{creds}"
      end
    end

    currencies = hotkeys.map { |_, params| params['currency'] }
    currencies += opts(:observe).keys
    currencies = currencies.flatten.compact.uniq.join(',')
    result['Show User Info'] = "ruby #{script_path} --action=user_info --currency=#{currencies} #{creds}"

    result
  end

  def prepare_observe(currency_key, ticker)
    observes = opts(:observe)[currency_key]
    return [] if observes.size.zero?
    step = opts(:step) || DEFAULT_STEP # step from user options or 5%

    ["Observers: "] + observes.map do |observe|
      observe.map do |identy, order|
        state = '[|]'
        order_type, order_val = order.to_a[0]
        prcent = calc_prcent(order_type, order_val, ticker)
        rnd = prcent.round(3).abs
        state = "[#{prcent > 0.01 ? UP_SYMBOL : DOWN_SYMBOL}#{rnd}]"
        color = "| color=#{prcent > 0.01 ? 'green' : 'red'}" if rnd > step

        " -- #{state} #{identy} #{order_type}: #{order_val} #{color}"
      end
    end.flatten
  end

  def prepare_history(currency_key)
    history_list = opts(:history)[currency_key]
    return [] if history_list.nil? || history_list.size.zero?

    ["History: "] + history_list.map do |history|
      history.map do |identy, order|
        order_type, order_val = order.to_a[0]
        " -- #{identy} #{order_type}: #{order_val}"
      end
    end.flatten
  end

  def prepare_observe_state(currency_key, ticker)
    observes = opts(:observe)[currency_key]
    return nil if observes.size.zero?

    observes.map do |observe|
      observe.map do |_, order|
        order_type, order_val = order.to_a[0]
        calc_prcent(order_type, order_val, ticker)
      end
    end.flatten.min
  end

  def calc_prcent(order_type, order_val, ticker)
    if order_type == 'buy'
      price = ticker['sell_price'].to_f

      (price - order_val) / order_val * 100
    elsif order_type == 'sell'
      price = ticker['buy_price'].to_f

      (order_val - price) / order_val * 100
    else
      raise ArgumentError, "Wrong type argument, can be only buy or sell!"
    end
  end

  def prepare_ticker(ticker)
    ignore_keys = %w[vol vol_curr]
    ["Tickers: "] + ticker.map do |k, v|
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
      ticker: {
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

  def get_symbol(currency)
    from, to = currency.split('_')
    SYMBOLS_MAP[from]
  end

  def opts(key)
    options.dig(key.to_s)
  end
end

class ExmoTradeScript
  attr_reader :action, :currency, :value, :credential_key, :credential_secret

  def self.run(*args)
    opts = args.flatten.each_with_object({}) do |arg, memo|
      match = /^-?-(?<key>.*?)(=(?<value>.*)|)$/.match(arg)
      memo[match[:key]] = match[:value] if match
    end
    # return p opts

    inst = self.new(opts)
    inst.perform!
  end

  MIN_QUANTITY_VAL = 0.0001.freeze

  #
  # @param options [Hash]
  #   @option action [String] options (required) - one of %i[market_buy market_sell] or 'user_info'
  #   @option currency [String] options (required) - example: "BTC_USD,BTC_EUR"
  #   @option value [Float] options (required) -  example: "0.0001 BTC" or "35 USD"
  #   @option credential_key [String] options (required)
  #   @option credential_secret [String] options (required)
  #
  def initialize(options)
    @options = options

    if initial_options_valid?(@options)
      @action = opts(:action)
      @currency = opts(:currency)
      @value = opts(:value)
      @credential_key = opts(:credential_key) || '__KEY__'
      @credential_secret = opts(:credential_secret) || '__SECRET__'
    else
      raise ArgumentError, "Not found needed arguments or config file wrong!"
    end
  end

  def perform!
    user = api_query('user_info')
    return show_user_info(user) if action == 'user_info'

    ticker = api_query('ticker')[currency]
    raise StandardError, "Currency #{currency} wasn't found on the server!" if ticker.nil?

    quantity = case action
      when 'market_buy'
        # convert to source (BTC)
        convert_to_source_currency(value, ticker)
        # @todo: update obcervers in config file
      when 'market_sell'
        # convert to source (BTC)
        convert_to_source_currency(value, ticker)
        # @todo: update obcervers in config file
      end

    order_params = {
      pair: currency,
      quantity: quantity,
      price: 0,
      type: action
    }

    if (violations = validate_order?(user, order_params)).any?
      raise StandardError, 'You cannot create order because of: ' + violations.join('; ')
    end

    puts "You will create order: #{order_params.inspect}"
    puts "  current prices: [sell: #{ticker['sell_price']}, buy: #{ticker['buy_price']} \n ----"
    order = api_query('order_create', order_params)
    if order['result']
      puts 'Creation SUCCESS, see order info:'
      puts api_query('order_trades', order_id: order['order_id'])
    else
      puts "Creating FAILED, errors: #{order['error']}"
    end
  end

  private

  def show_user_info(user)
    puts "---- \n"
    if currency.nil?
      puts(user.inspect)
    else
      currencies = currency.split(',').map { |c| c.split('_') }.flatten.compact.uniq
      filtered_data = user
      filtered_data['balances'] = user['balances'].select{ |k,v| currencies.include?(k) }
      filtered_data['reserved'] = user['reserved'].select{ |k,v| currencies.include?(k) }
      puts filtered_data
    end
  end


  def validate_order?(user, order_params)
    errors = []

    errors << 'Wrong quantity value' if order_params[:quantity].nil?
    errors << 'Wrong quantity type' unless order_params[:quantity].is_a?(Float)
    unless order_params[:quantity] >= MIN_QUANTITY_VAL
      errors << "Quantity less then #{MIN_QUANTITY_VAL}"
    end

    source, destination = order_params[:pair].split('_')
    case order_params[:type]
    when 'market_buy'
      balance = user['balances'][destination].to_f
      unless balance >= order_params[:quantity]
        errors << "#{balance} #{destination} on the user balance and it's less then needed (#{quantity})"
      end
    when 'market_sell'
      balance = user['balances'][source].to_f
      unless balance >= order_params[:quantity]
        errors << "#{balance} #{destination} on the user balance and it's less then needed (#{quantity})"
      end
    end

    errors
  end

  #
  # Should convert value with currenty to a source currency
  # if BTC_USD:
  #   0.0001 BTC => BTC = 0.0001
  #   35 USD => BTC = 35 * sell_price
  #
  # @param val [String] example: "0.001 BTC" or "35USD"
  #
  # @return [Float] val in source currency
  def convert_to_source_currency(val, ticker)
    source, destination = currency.split('_')
    matcher = parse_value(val)
    case matcher[:type]
    when source then matcher[:amount].to_f
    when destination then matcher[:amount].to_f * ticker['sell_price'].to_f
    else
      raise ArgumentError, "Wrong currenty in value"
    end
  end

  # @todo: Not needed remove me!
  # #
  # # Should convert value with currenty to a source currency
  # # if BTC_USD:
  # #   0.0001 BTC => USD = 0.0001 * buy_price
  # #   35 USD => USD = 35
  # #
  # # @param val [String] example: "0.001 BTC" or "35 USD"
  # #
  # # @return [Float] val in destination currency
  # def convert_to_destination_currency(val, ticker)
  #   source, destination = currency.split('_')
  #   matcher = parse_value(val)
  #   case matcher[:type]
  #   when source then matcher[:amount].to_f * ticker['buy_price'].to_f
  #   when destination then matcher[:amount].to_f
  #   else
  #     raise ArgumentError, "Wrong currenty in value"
  #   end
  # end

  def parse_value(val)
    /^(?<amount>\d*(\.\d*)?)\s*(?<type>[A-Z]+)$/.match(val)
  end

  def initial_options_valid?(options)
    return true
    # return false unless @options.key?(:action) && %w[market_buy market_sell].include?(opts(:action))
  end

  def api_query(method, params = nil)
    raise ArgumentError unless method.is_a?(String) || method.is_a?(Symbol)

    params = {} if params.nil?
    params['nonce'] = nonce

    uri = URI.parse(['https://api.exmo.com/v1', method].join('/'))

    post_data = URI.encode_www_form(params)

    digest = OpenSSL::Digest.new('sha512')
    sign = OpenSSL::HMAC.hexdigest(digest, credential_secret, post_data)

    headers = {
      'Sign' => sign,
      'Key'  => credential_key
    }

    req = Net::HTTP::Post.new(uri.path, headers)
    req.body = post_data
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

    JSON.load result
  end

  def valid_json?(json)
    JSON.parse(json)
    true
  rescue
    false
  end

  def nonce
    Time.now.strftime("%s%6N")
  end

  def opts(key, default = nil)
    @options.fetch(key.to_s, default)
  end
end

ExmoTradeScript.run(ARGV) if ARGV.any?
