class SierraApiClientError < StandardError
end

class SierraApiClientTokenError < SierraApiClientError
end

class SierraApiResponseError < StandardError
  attr_reader :response
  
  def initialize(response)
    @response = response
  end
end
