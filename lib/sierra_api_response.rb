class SierraApiResponse
  attr_accessor :response

  def initialize(response)
    @response = response
  end

  def code
    @response.code.to_i
  end

  def error?
    code >= 400
  end

  def success?
    (200...300).include? code
  end

  def body
    return @response.body if @response.code == '204' 

    # If response Content-Type indicates body is json
    if /^application\/json/ =~ @response['Content-Type'] 
      begin
        JSON.parse(@response.body)
      rescue => e
        raise SierraApiResponseError.new(response), "Error parsing response (#{response.code}): #{response.body}"
      end
    else
      @response.body
    end
  end
end
