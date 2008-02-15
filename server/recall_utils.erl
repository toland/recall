%%---------------------------------------------------------------------------
%% Utility functions used by the Recall Mnesia client.

-module(recall_utils).
-import(lists, [append/2]).
-import(string, [to_lower/1]).
-export([send_success/1,
         send_success/2,
         send_error/2,
         socket_send/2,
         binary_to_atom/1,
         binary_list_to_atom_list/1,
         binary_list_to_string_list/1,
         list_to_record/1,
         list_to_record/2,
         parse_command/1]).


%%---------------------------------------------------------------------------
%% Network utilities

% Send the generic success message "ok"
send_success(Socket) -> socket_send(Socket, json:encode([<<"ok">>])).

% Send a specific success message. The format of the message must be
% the same as the send_response() method.
send_success(Socket, Msg) -> send_response(Socket, ok, Msg).

% Send a specific failure message. The format of the message must be
% the same as the send_response() method.
send_error(Socket, Msg) -> send_response(Socket, error, Msg).

% Send a specific success message. If the message is a string it will be
% converted to a binary. Both binary and atoms will be encoded into 
% JSON strings. Raises an error if the message isn't a string, atom
% or binary. Lists that aren't strings and tuples aren't allowed.
send_response(Socket, Type, Msg) when is_atom(Msg) orelse is_binary(Msg) ->
    socket_send(Socket, json:encode([Type, Msg]));
send_response(Socket, Type, Msg) when is_list(Msg) ->
    socket_send(Socket, json:encode([Type, list_to_binary(Msg)])).

% Send a message guaranteeing that a CRLF pair is appended to the end.
socket_send(Socket, Msg) -> gen_tcp:send(Socket, Msg ++ "\r\n").


%%---------------------------------------------------------------------------
%% Conversion utilities

% Convert a binary to an atom. The binary must be a string.
binary_to_atom(Binary) -> list_to_atom(binary_to_list(Binary)).

% Convert a list of binaries to a list of atoms.
binary_list_to_atom_list(List) -> [binary_to_atom(Item) || Item <- List].

% Convert a list of binaries to a list of strings.
binary_list_to_string_list(List) -> [binary_to_list(Item) || Item <- List].

% Convert a list to a tuple in "record format". The list must begin with a
% string in binary format. That element will be converted to all lower case
% and then converted into an atom. Finally, the entire list will be converted
% into a tuple. For example, the list [<<"FOO">>, <<"bar">>, 4] will result in
% this tuple: {foo, <<"bar">>, 4}.
list_to_record([H|T]) -> list_to_record(H, T).
list_to_record(Id, List) ->
    list_to_tuple(append([list_to_atom(to_lower(binary_to_list(Id)))], List)).

% Parses a command in a JSON array into a command tuple in record format.
parse_command(CmdStr) ->
    case json:decode(CmdStr) of
        {ok, [Cmd|Args], _Rest} -> list_to_record(Cmd, Args);
        {error, Reason} -> {error, CmdStr, Reason}
    end.
