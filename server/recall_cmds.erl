%%---------------------------------------------------------------------------
%% This module contains the command implementations. This is the code that 
%% actually interacts with Mnesia. Each command is implemented by adding a
%% clause to the do_command/2 function.

-module(recall_cmds).
-export([do_command/2]).
-import(recall_utils, [send_success/1,
                       send_success/2,
                       send_error/2,
                       binary_to_atom/1,
                       binary_list_to_atom_list/1]).


% Parse the result returned from an Mnesia function and send the result to the client.
send_mnesia_result(Socket, Result) ->
    case Result of
        {atomic, ok} -> send_success(Socket);
        {atomic, Val} -> send_success(Socket, Val);
        {aborted, Reason} ->
            io:fwrite("~p~n", Reason),
            send_error(Socket, mnesia:error_description(Reason))
    end.


% Echo the argument back to the client.
do_command(Socket, {echo, Arg}) ->
    send_success(Socket, binary_to_list(Arg));

% Create a new table in Mnesia named 'Name' with the fields names listed in 'Fields'.
do_command(Socket, {mktable, Name, Fields}) ->
    Result = mnesia:create_table(binary_to_atom(Name), 
                [{disc_copies,  [node()]},
                 {attributes,  binary_list_to_atom_list(Fields)}]),
    send_mnesia_result(Socket, Result);

% Delete the Mnesia table named 'Name'.
do_command(Socket, {rmtable, Name}) ->
    send_mnesia_result(Socket, mnesia:delete_table(binary_to_atom(Name)));

% This clause is called when there is an error parsing the command.
do_command(Socket, {error, CmdStr, Reason}) ->
    io:fwrite("--> Error parsing command ~s...~n", [CmdStr]),
    send_error(Socket, Reason);

% This clause is called when the command has been successfully parsed, but it
% doesn't match an existing command sequence.
do_command(Socket, CmdList) ->
    io:fwrite("--> Calling default handler for command ~p...~n", CmdList),
    send_error(Socket, "Unkown command").
