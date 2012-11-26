module MongodbLogger
  module Adapers
    class Mongo < Base
      
      def initialize(options = {})
        @authenticated = false
        @configuration = options
        if @configuration['url']
          uri = URI.parse(@configuration['url'])
          @configuration['database'] = uri.path.gsub(/^\//, '')
          @connection ||= mongo_connection_object.db(@configuration['database'])
          @authenticated = true
        else
          @connection ||= mongo_connection_object.db(@configuration['database'])
          if @configuration['username'] && @configuration['password']
            # the driver stores credentials in case reconnection is required
            @authenticated = @connection.authenticate(@configuration['username'],
                                                          @configuration['password'])
          end
        end
      end
      
      def create_collection
        @connection.create_collection(collection_name,
          {:capped => true, :size => @configuration['capsize'].to_i})
      end
      
      def insert_log_record(record, options = {})
        @collection.insert(record, options)
      end
      
      def collection_stats
        stats = @collection.stats
        {
          :is_capped => (stats["capped"] && ([1, true].include?(stats["capped"]))),
          :count => stats["count"],
          :size => stats["size"],
          :storageSize => stats["storageSize"],
          :db_name => @configuration["database"],
          :collection => collection_name
        } 
      end
      
      # filter
      def filter_by_conditions(filter)
        @collection.find(filter.get_mongo_conditions).sort('$natural', -1).limit(filter.get_mongo_limit)
      end
      
      def find_by_id(id)
        @collection.find_one(BSON::ObjectId(id))
      end
      
      def tail_log_from_params(params = {})
        logs = []
        last_id = nil
        if params[:log_last_id] && !params[:log_last_id].blank?
          log_last_id = params[:log_last_id]
          tail = ::Mongo::Cursor.new(@collection, :tailable => true, :order => [['$natural', 1]], 
            :selector => {'_id' => { '$gt' => BSON::ObjectId(log_last_id) }})
          while log = tail.next
            logs << log
            log_last_id = log["_id"].to_s
          end
          logs.reverse!
        else
          log = @collection.find_one({}, {:sort => ['$natural', -1]})
          log_last_id = log["_id"].to_s unless log.blank?
        end
        { 
          :log_last_id => log_last_id, 
          :time => Time.now.strftime("%F %T"),
          :logs => logs
        }
      end
      
      private
      
      def mongo_connection_object
        if @configuration['hosts']
          conn = ::Mongo::ReplSetConnection.new(*(@configuration['hosts'] <<
            {:connect => true, :pool_timeout => 6}))
          @configuration['replica_set'] = true
        elsif @configuration['url']
          conn = ::Mongo::Connection.from_uri(@configuration['url'])
        else
          conn = ::Mongo::Connection.new(@configuration['host'],
                                       @configuration['port'],
                                       :connect => true,
                                       :pool_timeout => 6)
        end
        @connection_type = conn.class
        conn
      end
      
    end
  end
end