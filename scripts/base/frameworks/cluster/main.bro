##! A framework for establishing and controlling a cluster of Bro instances.
##! In order to use the cluster framework, a script named
##! ``cluster-layout.bro`` must exist somewhere in Bro's script search path
##! which has a cluster definition of the :bro:id:`Cluster::nodes` variable.
##! The ``CLUSTER_NODE`` environment variable or :bro:id:`Cluster::node`
##! must also be sent and the cluster framework loaded as a package like
##! ``@load base/frameworks/cluster``.

@load base/frameworks/control
@load base/frameworks/broker

module Cluster;

export {
	## Whether the cluster framework uses broker to perform remote communication.
	const use_broker = T &redef;

	## Whether to distribute log messages among available logging nodes.
	const enable_round_robin_logging = T &redef;

	## The topic name used for exchanging general messages that are relevant to
	## any node in a cluster.  Used with broker-enabled cluster communication.
	const broadcast_topic = "bro/cluster/broadcast" &redef;

	## The topic name used for exchanging messages that are relevant to
	## logger nodes in a cluster.  Used with broker-enabled cluster communication.
	const logger_topic = "bro/cluster/logger" &redef;

	## The topic name used for exchanging messages that are relevant to
	## manager nodes in a cluster.  Used with broker-enabled cluster communication.
	const manager_topic = "bro/cluster/manager" &redef;

	## The topic name used for exchanging messages that are relevant to
	## proxy nodes in a cluster.  Used with broker-enabled cluster communication.
	const proxy_topic = "bro/cluster/proxy" &redef;

	## The topic name used for exchanging messages that are relevant to
	## worker nodes in a cluster.  Used with broker-enabled cluster communication.
	const worker_topic = "bro/cluster/worker" &redef;

	## The topic name used for exchanging messages that are relevant to
	## time machine nodes in a cluster.  Used with broker-enabled cluster communication.
	const time_machine_topic = "bro/cluster/time_machine" &redef;

	## The topic prefix used for exchanging messages that are relevant to
	## a named node in a cluster.  Used with broker-enabled cluster communication.
	const node_topic_prefix = "bro/cluster/node/" &redef;

	## Name of the node on which master data stores will be created if no other
	## has already been specified by the user in :bro:see:`Cluster::stores`.
	const default_master_node = "manager" &redef;

	## The type of data store backend that will be used for all data stores if
	## no other has already been specified by the user in :bro:see:`Cluster::stores`.
	const default_backend = Broker::MEMORY &redef;

	## The type of persistent data store backend that will be used for all data
	## stores if no other has already been specified by the user in
	## :bro:see:`Cluster::stores`.  This will be used when script authors call
	## :bro:see:`Cluster::create_store` with the *persistent* argument set true.
	const default_persistent_backend = Broker::SQLITE &redef;

	## Setting a default dir will, for persistent backends that have not
	## been given an explicit file path via :bro:see:`Cluster::stores`,
	## automatically create a path within this dir that is based on the name of
	## the data store.
	const default_store_dir = "" &redef;

	## Information regarding a cluster-enabled data store.
	type StoreInfo: record {
		## The name of the data store.
		name: string &optional;
		## The store handle.
		store: opaque of Broker::Store &optional;
		## The name of the cluster node on which the master version of the data
		## store resides.
		master_node: string &default=default_master_node;
		## Whether the data store is the master version or a clone.
		master: bool &default=F;
		## The type of backend used for storing data.
		backend: Broker::BackendType &default=default_backend;
		## Parameters used for configuring the backend.
		options: Broker::BackendOptions &default=Broker::BackendOptions();
	};

	## A table of cluster-enabled data stores that have been created, indexed
	## by their name.  This table will be populated automatically by
	## :bro:see:`Cluster::create_store`, but if you need to customize
	## the options related to a particular data store, you may redef this
	## table.  Calls to :bro:see:`Cluster::create_store` will first check
	## the table for an entry of the same name and, if found, will use the
	## predefined options there when setting up the store.
	global stores: table[string] of StoreInfo &default=StoreInfo() &redef;

	## Sets up a cluster-enabled data store.  They will also still properly
	## function for uses that are not operating a cluster.
	##
	## name: the name of the data store to create.
	##
	## persistent: whether the data store must be persistent.
	##
	## Returns: the store's information.  For master stores, the store will be
	##          ready to use immediately.  For clones, the store field will not
	##          be set until the node containing the master store has connected.
	global create_store: function(name: string, persistent: bool &default=F): StoreInfo;

	## The cluster logging stream identifier.
	redef enum Log::ID += { LOG };

	## The record type which contains the column fields of the cluster log.
	type Info: record {
		## The time at which a cluster message was generated.
		ts:       time;
		## The name of the node that is creating the log record.
		node: string;
		## A message indicating information about the cluster's operation.
		message:  string;
	} &log;

	## Types of nodes that are allowed to participate in the cluster
	## configuration.
	type NodeType: enum {
		## A dummy node type indicating the local node is not operating
		## within a cluster.
		NONE,
		## A node type which is allowed to view/manipulate the configuration
		## of other nodes in the cluster.
		CONTROL,
		## A node type responsible for log management.
		LOGGER,
		## A node type responsible for policy management.
		MANAGER,
		## A node type for relaying worker node communication and synchronizing
		## worker node state.
		PROXY,
		## The node type doing all the actual traffic analysis.
		WORKER,
		## A node acting as a traffic recorder using the
		## `Time Machine <http://bro.org/community/time-machine.html>`_
		## software.
		TIME_MACHINE,
	};

	## Events raised by a manager and handled by the workers.
	const manager2worker_events = /Drop::.*/ &redef;

	## Events raised by a manager and handled by proxies.
	const manager2proxy_events = /EMPTY/ &redef;

	## Events raised by a manager and handled by loggers.
	const manager2logger_events = /EMPTY/ &redef;

	## Events raised by proxies and handled by loggers.
	const proxy2logger_events = /EMPTY/ &redef;

	## Events raised by proxies and handled by a manager.
	const proxy2manager_events = /EMPTY/ &redef;

	## Events raised by proxies and handled by workers.
	const proxy2worker_events = /EMPTY/ &redef;

	## Events raised by workers and handled by loggers.
	const worker2logger_events = /EMPTY/ &redef;

	## Events raised by workers and handled by a manager.
	const worker2manager_events = /(TimeMachine::command|Drop::.*)/ &redef;

	## Events raised by workers and handled by proxies.
	const worker2proxy_events = /EMPTY/ &redef;

	## Events raised by TimeMachine instances and handled by a manager.
	const tm2manager_events = /EMPTY/ &redef;

	## Events raised by TimeMachine instances and handled by workers.
	const tm2worker_events = /EMPTY/ &redef;

	## Events sent by the control host (i.e., BroControl) when dynamically
	## connecting to a running instance to update settings or request data.
	const control_events = Control::controller_events &redef;

	## Record type to indicate a node in a cluster.
	type Node: record {
		## Identifies the type of cluster node in this node's configuration.
		node_type:    NodeType;
		## The IP address of the cluster node.
		ip:           addr;
		## If the *ip* field is a non-global IPv6 address, this field
		## can specify a particular :rfc:`4007` ``zone_id``.
		zone_id:      string      &default="";
		## The port that this node will listen on for peer connections.
		p:            port;
		## Identifier for the interface a worker is sniffing.
		interface:    string      &optional;
		## Name of the logger node this node uses.  For manager, proxies and workers.
		logger:       string      &optional;
		## Name of the manager node this node uses.  For workers and proxies.
		manager:      string      &optional;
		## Name of the proxy node this node uses.  For workers and managers.
		proxy:        string      &optional;
		## Names of worker nodes that this node connects with.
		## For managers and proxies.
		workers:      set[string] &optional;
		## Name of a time machine node with which this node connects.
		time_machine: string      &optional;
		## A unique identifier assigned to the node by the broker framework.
		## This field is only set while a node is connected.
		id: string                &optional;
	};

	## This function can be called at any time to determine if the cluster
	## framework is being enabled for this run.
	##
	## Returns: True if :bro:id:`Cluster::node` has been set.
	global is_enabled: function(): bool;

	## This function can be called at any time to determine what type of
	## cluster node the current Bro instance is going to be acting as.
	## If :bro:id:`Cluster::is_enabled` returns false, then
	## :bro:enum:`Cluster::NONE` is returned.
	##
	## Returns: The :bro:type:`Cluster::NodeType` the calling node acts as.
	global local_node_type: function(): NodeType;

	## This gives the value for the number of workers currently connected to,
	## and it's maintained internally by the cluster framework.  It's
	## primarily intended for use by managers to find out how many workers
	## should be responding to requests.
	global worker_count: count = 0;

	## The cluster layout definition.  This should be placed into a filter
	## named cluster-layout.bro somewhere in the BROPATH.  It will be
	## automatically loaded if the CLUSTER_NODE environment variable is set.
	## Note that BroControl handles all of this automatically.
	## The table is typically indexed by node names/labels (e.g. "manager"
	## or "worker-1").
	const nodes: table[string] of Node = {} &redef;

	## Indicates whether or not the manager will act as the logger and receive
	## logs.  This value should be set in the cluster-layout.bro script (the
	## value should be true only if no logger is specified in Cluster::nodes).
	## Note that BroControl handles this automatically.
	const manager_is_logger = T &redef;

	## This is usually supplied on the command line for each instance
	## of the cluster that is started up.
	const node = getenv("CLUSTER_NODE") &redef;

	## Interval for retrying failed connections between cluster nodes.
	const retry_interval = 1min &redef;

	## When using broker-enabled cluster framework, nodes broadcast this event
	## to exchange their user-defined name along with a string that uniquely
	## identifies it for the duration of its lifetime.  This string may change
	## if the node dies and has to reconnect later.
	global hello: event(name: string, id: string);

	## When using broker-enabled cluster framework, this event will be emitted
	## locally whenever a cluster node connects or reconnects.
	global node_up: event(name: string, id: string);

	## When using broker-enabled cluster framework, this event will be emitted
	## locally whenever a connected cluster node becomes disconnected.
	global node_down: event(name: string, id: string);

	## Write a message to the cluster logging stream.
	global log: function(msg: string);

	## Retrieve the topic associated with a specific node in the cluster.
	##
	## name: the name of the cluster node (e.g. "manager").
	##
	## Returns: a topic string that may used to send a message exclusively to
	##          a given cluster node.
	global node_topic: function(name: string): string;
}

type NamedNode: record {
	name: string;
	node: Node;
};

function nodes_with_type(node_type: NodeType): vector of NamedNode
	{
	local rval: vector of NamedNode = vector();
	local names: vector of string = vector();

	for ( name in Cluster::nodes )
		names[|names|] = name;

	names = sort(names, strcmp);

	for ( i in names )
		{
		name = names[i];
		local n = Cluster::nodes[name];

		if ( n$node_type != node_type )
			next;

		rval[|rval|] = NamedNode($name=name, $node=n);
		}

	return rval;
	}

function is_enabled(): bool
	{
	return (node != "");
	}

function local_node_type(): NodeType
	{
	return is_enabled() ? nodes[node]$node_type : NONE;
	}

function node_topic(name: string): string
	{
	return node_topic_prefix + name;
	}

event remote_connection_handshake_done(p: event_peer) &priority=5
	{
	if ( p$descr in nodes && nodes[p$descr]$node_type == WORKER )
		{
		if ( use_broker )
			Reporter::error(fmt("broker-enabled cluster using old comms: '%s' ", node));
		else
			++worker_count;
		}
	}

event remote_connection_closed(p: event_peer) &priority=5
	{
	if ( p$descr in nodes && nodes[p$descr]$node_type == WORKER )
		{
		if ( use_broker )
			Reporter::error(fmt("broker-enabled cluster using old comms: '%s' ", node));
		else
			--worker_count;
		}
	}

event Cluster::hello(name: string, id: string) &priority=10
	{
	if ( name !in nodes )
		{
		Reporter::error(fmt("Got Cluster::hello msg from unexpected node: %s", name));
		return;
		}

	local n = nodes[name];

	if ( n?$id )
		{
		if ( n$id != id )
			Reporter::error(fmt("Got Cluster::hello msg from duplicate node:%s",
								name));
		}
	else
		event Cluster::node_up(name, id);

	n$id = id;
	Cluster::log(fmt("got hello from %s (%s)", name, id));

	if ( n$node_type == WORKER )
		++worker_count;

	for ( store_name in stores )
		{
		local info = stores[store_name];

		if ( info?$store )
			next;

		if ( info$master )
			next;

		if ( info$master_node == name )
			{
			info$store = Broker::create_clone(info$name);
			Cluster::log(fmt("created clone store: %s", info$name));
			}
		}
	}

event Broker::peer_added(endpoint: Broker::EndpointInfo, msg: string) &priority=10
	{
	if ( ! use_broker )
		return;

	if ( ! Cluster::is_enabled() )
		return;

	local e = Broker::make_event(Cluster::hello, node, Broker::node_id());
	Broker::publish(Cluster::broadcast_topic, e);
	}

event Broker::peer_lost(endpoint: Broker::EndpointInfo, msg: string) &priority=10
	{
	if ( ! use_broker )
		return;

	for ( node_name in nodes )
		{
		local n = nodes[node_name];

		if ( n?$id && n$id == endpoint$id )
			{
			Cluster::log(fmt("node down: %s", node_name));
			delete n$id;

			if ( n$node_type == WORKER )
				--worker_count;

			for ( store_name in stores )
				{
				local info = stores[store_name];

				if ( ! info?$store )
					next;

				if ( info$master )
					next;

				if ( info$master_node == node_name )
					{
					Broker::close(info$store);
					delete info$store;
					Cluster::log(fmt("clone store closed: %s", info$name));
					}
				}

			event Cluster::node_down(node_name, endpoint$id);
			break;
			}
		}
	}

event bro_init() &priority=5
	{
	# If a node is given, but it's an unknown name we need to fail.
	if ( node != "" && node !in nodes )
		{
		Reporter::error(fmt("'%s' is not a valid node in the Cluster::nodes configuration", node));
		terminate();
		}

	Log::create_stream(Cluster::LOG, [$columns=Info, $path="cluster"]);
	}

function create_store(name: string, persistent: bool &default=F): Cluster::StoreInfo
	{
	local info = stores[name];
	info$name = name;

	if ( Cluster::default_store_dir != "" )
		{
		local default_options = Broker::BackendOptions();
		local path = Cluster::default_store_dir + "/" + name;

		if ( info$options$sqlite$path == default_options$sqlite$path )
			info$options$sqlite$path = path + ".sqlite";

		if ( info$options$rocksdb$path == default_options$rocksdb$path )
			info$options$rocksdb$path = path + ".rocksdb";
		}

	if ( persistent )
		{
		switch ( info$backend ) {
		case Broker::MEMORY:
			info$backend = Cluster::default_persistent_backend;
			break;
		case Broker::SQLITE:
			fallthrough;
		case Broker::ROCKSDB:
			# no-op: user already asked for a specific persistent backend.
			break;
		default:
			Reporter::error(fmt("unhandled data store type: %s", info$backend));
			break;
		}
		}

	if ( ! Cluster::is_enabled() )
		{
		if ( info?$store )
			{
			Reporter::warning(fmt("duplicate cluster store creation for %s", name));
			return info;
			}

		info$store = Broker::create_master(name, info$backend, info$options);
		info$master = T;
		stores[name] = info;
		Cluster::log(fmt("created master store: %s", name));
		return info;
		}

	if ( info$master_node !in Cluster::nodes )
		Reporter::fatal(fmt("master node '%s' for cluster store '%s' does not exist",
		                    info$master_node, name));

	if ( Cluster::node == info$master_node )
		{
		info$store = Broker::create_master(name, info$backend, info$options);
		info$master = T;
		stores[name] = info;
		return info;
		}

	info$master = F;
	stores[name] = info;
	Cluster::log(fmt("pending clone store creation: %s", name));
	return info;
	}

function log(msg: string)
	{
	Log::write(Cluster::LOG, [$ts = network_time(), $node = node, $message = msg]);
	}
