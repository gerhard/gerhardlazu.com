MongoMapper.connection = Mongo::Connection.new('localhost', nil, :logger => logger)

case Padrino.env
  when :development then MongoMapper.database = 'gerhardlazu.com_development'
  when :production  then MongoMapper.database = 'gerhardlazu.com_production'
  when :test        then MongoMapper.database = 'gerhardlazu.com_test'
end
