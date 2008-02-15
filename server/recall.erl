%%---------------------------------------------------------------------------
%% This is the main driver for the Recall Mnesia client.

-module(recall).
-export([boot/0, start/0, start_mnesia_standalone/0]).
-export([start_listener/1,
         accept_clients/2,
         register_client/2,
         loop/1,
         client_loop/2]).
-include("recall.hrl").
-import(recall_cmds, [do_command/2]).
-import(recall_utils, [parse_command/1,
                       socket_send/2,
                       send_success/2,
                       send_error/2]).


% Start a standalone Mnesia node and then start Recall.
boot() ->
    start_mnesia_standalone(),
    start().


% Start Mnesia on this node only.
start_mnesia_standalone() ->
    mnesia:create_schema([node()]),
    mnesia:start().


% Start the Recall client listener in a new process.
start() -> spawn(?MODULE, start_listener, [?DEFAULT_PORT]).


% Open the socket used to listen for connections and start the main loop
% in a new process.
start_listener(Port) ->
    {ok, Socket} = gen_tcp:listen(Port, [{packet, 0}, {active, false}]),
    Accepter = spawn_link(?MODULE, accept_clients, [Socket, self()]),
    io:fwrite("--> Recall Server Started on port ~B...~n", [Port]),
    loop(#session{socket = Socket, accepter = Accepter, clients = []}).


% The main loop which maintains the client list and a few bookkeeping tasks.
loop(Session = #session{accepter = A, clients = Cs}) ->
    receive
        {'new client', Client} ->
            erlang:monitor(process, Client#client.pid),
            Cs1 = [Client|Cs],
            io:fwrite("--> new connection from ~s\r\n", [Client#client.name]),
            loop(Session#session{clients = Cs1});

        {'DOWN', _, process, Pid, _Info} ->
            case lists:keysearch(Pid, #client.pid, Cs) of
                false -> loop(Session);
                {value, Client} -> 
                    self() ! {'lost client', Client},
                    loop(Session)
            end;

        {'lost client', Client} ->
            io:fwrite("--> lost connection from ~s\r\n", [Client#client.name]),
            gen_tcp:close(Client#client.socket),
            loop(Session#session{clients = lists:delete(Client, Cs)});

        refresh ->
            io:fwrite("--> Refreshing Recall server...", []),
            A ! refresh,
            lists:foreach(fun (#client{pid=CP}) -> CP ! refresh end, Cs),
            ?MODULE:loop(Session);

        quit ->
            io:fwrite("--> Exiting Recall server...", []),
            A ! quit,
            lists:foreach(fun (#client{pid=CP}) -> CP ! quit end, Cs)
    end.


% Listens for new client connections.
accept_clients(Socket, Server) ->
    case gen_tcp:accept(Socket) of
        {ok, Client} -> spawn(?MODULE, register_client, [Client, Server]);
        {error, Reason} -> io:fwrite("--> Error connecting to client: ~s~n", [Reason]) 
    end,
    receive
        refresh -> ?MODULE:accept_clients(Socket, Server);
        quit -> gen_tcp:close(Socket)
    after 0 -> accept_clients(Socket, Server)
    end.


% Called when a new client connects. Handles identifying the client and passes
% the Client record back to the main loop. Once the client has been identified
% the client_loop is started.
register_client(Socket, Server) ->
    socket_send(Socket, "Welcome to Recall. Connect with 'CONNECT name'."),
    {ok, N} = gen_tcp:recv(Socket, 0),
    case parse_command(N) of
        {connect, Name} ->
            Client = #client{socket=Socket, name=binary_to_list(Name), pid=self()},
            Server ! {'new client', Client},
            send_success(Socket, "Connected"),
            client_loop(Client, Server);

        _ ->
            send_error(Socket, "That wasn't sensible, sorry."),
            gen_tcp:close(Socket)
    end.


% Receives, parses and dispatches commands sent by the client.
client_loop(Client = #client{socket = Socket}, Server) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Recv} -> do_command(Socket, parse_command(Recv));
        {error, _} -> Server ! {'lost client', Client}
    end,
    receive
        refresh -> ?MODULE:client_loop(Client, Server);
        quit -> gen_tcp:close(Socket)
    after 0 -> client_loop(Client, Server)
    end.
