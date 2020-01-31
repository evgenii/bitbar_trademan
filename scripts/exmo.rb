class Exmo
  attr_reader :currency_key, :options

  def initialize(currency_key, options = {})
    @currency_key = currency_key
    raise ArgumentError "currency_key should be defined" unless @currency_key = currency_key

    @options = options
  end

  def preform
    {
      iconImg: nil,
      iconSym: '[√]',
      title: 'title',
      description: [
        'description: value 1'
      ]
    }
  end

  private

  def opts(key)
    options.dig(key)
  end
end
