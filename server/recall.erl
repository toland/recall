-module(recall).
-export([start/0]).
-export([start_listener/1, accept_clients/2, register_client/2, loop/1, client_loop/2]).
-compile(export_all).


-define(DEFAULT_PORT, 9900).

-record(session, {socket, accepter, clients}).
-record(client, {socket, name, pid}).


start() -> 
    spawn(?MODULE, start_listener, [?DEFAULT_PORT]).

start_listener(Port) ->
    {ok, Socket} = gen_tcp:listen(Port, [{packet, 0}, {active, false}]),
    Accepter = spawn_link(?MODULE, accept_clients, [Socket, self()]),
	io:fwrite("--> Recall Server Started on port ~B...~n", [Port]),
    loop(#session{socket = Socket, accepter = Accepter, clients = []}).


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

socket_send(Socket, Msg) -> gen_tcp:send(Socket, Msg ++ "\r\n").


send_success(Socket) -> socket_send(Socket, json:encode([<<"ok">>])).

send_success(Socket, Msg) when is_atom(Msg) ->
    socket_send(Socket, json:encode([<<"ok">>, Msg]));
send_success(Socket, Msg) when is_list(Msg) ->
    socket_send(Socket, json:encode([<<"ok">>, list_to_binary(Msg)])).

send_error(Socket, Reason) ->
    socket_send(Socket, json:encode([<<"error">>, list_to_binary(Reason)])).

send_mnesia_result(Socket, Result) ->
    case Result of 
        {atomic, ok} -> send_success(Socket);
        {atomic, Val} -> send_success(Socket, Val);
        {aborted, Reason} -> 
            io:fwrite("~p~n", Reason),
            send_error(Socket, mnesia:error_description(Reason))
    end.

list_to_record(List) ->
    [H|T] = List,
    list_to_record(H, T).

list_to_record(Id, List) ->
    list_to_tuple(lists:append([list_to_atom(string:to_lower(binary_to_list(Id)))], List)).

parse_command(CmdStr) ->
    case json:decode(CmdStr) of
        {ok, [Cmd|Args], _Rest} -> list_to_record(Cmd, Args);
        {error, Reason} -> {error, CmdStr, Reason}
    end.

binary_to_atom(Binary) -> list_to_atom(binary_to_list(Binary)).
binary_list_to_atom_list(List) -> [binary_to_atom(Item) || Item <- List].
binary_list_to_string_list(List) -> [binary_to_list(Item) || Item <- List].

do_command(Socket, {echo, Arg}) ->
    send_success(Socket, binary_to_list(Arg));
do_command(Socket, {mktable, Name, Fields}) ->
    Result = mnesia:create_table(binary_to_atom(Name), 
                [{disc_copies,  [node()]}, 
                 {attributes,  binary_list_to_atom_list(Fields)}]),
    send_mnesia_result(Socket, Result);
do_command(Socket, {rmtable, Name}) ->
    send_mnesia_result(Socket, mnesia:delete_table(binary_to_atom(Name)));
do_command(Socket, {error, CmdStr, Reason}) ->
    io:fwrite("--> Error parsing command ~s...~n", [CmdStr]),
    send_error(Socket, Reason);
do_command(Socket, CmdList) ->
    io:fwrite("--> Calling default handler for command ~p...~n", CmdList),
    send_error(Socket, "Unkown command").

start_mnesia() ->
    mnesia:create_schema([node()]),
    mnesia:start().
