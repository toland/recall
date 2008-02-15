%%---------------------------------------------------------------------------
%% Macros and records used by the Recall Mnesia client.

-define(DEFAULT_PORT, 9900).

-record(session, {socket, accepter, clients}).
-record(client, {socket, name, pid}).
