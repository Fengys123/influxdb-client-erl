%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(influxdb_http).

-export([ is_alive/1
        , write/2
        , write/3
        , write_async/3
        , write_async/4]).

is_alive(Client = #{version := Version}) ->
    is_alive(Version, Client);
is_alive(Client) ->
    is_alive(v1, Client).

is_alive(v2, Client = #{headers := Headers}) ->
    Path = "/ping",
    try
        Worker = pick_worker(Client, ignore),
        case ehttpc:request(Worker, get, {Path, Headers}) of
            {ok, 200, _} ->
                true;
            {ok, 200, _, _} ->
                true;
            {ok, 204, _} ->
                true;
            {ok, 204, _, _} ->
                true;
            _ ->
                false
        end
    catch _E:_R:_S ->
        false
    end;
is_alive(v1, Client) ->
    Path = "/ping",
    Headers = [{<<"verbose">>, <<"true">>}],
    try
        Worker = pick_worker(Client, ignore),
        case ehttpc:request(Worker, get, {Path, Headers}) of
            {ok, 204, _} ->
                true;
            {ok, 204, _, _} ->
                true;
            _ ->
                false
        end
    catch E:R:S ->
        logger:error("[InfluxDB] is alive: ~0p ~0p ~0p", [E, R, S]),
        false
    end.

write(Client = #{path := Path, headers := Headers}, Data) ->
    Request = {Path, Headers, Data},
    do_write(pick_worker(Client, ignore), Request).

write(Client = #{path := Path, headers := Headers}, Key, Data) ->
    Request = {Path, Headers, Data},
    do_write(pick_worker(Client, Key), Request).

write_async(Client = #{path := Path, headers := Headers}, Data, ReplayFunAndArgs) ->
    Request = {Path, Headers, Data},
    do_aysnc_write(pick_worker(Client, ignore), Request, ReplayFunAndArgs).

write_async(Client = #{path := Path, headers := Headers}, Key, Data, ReplayFunAndArgs) ->
    Request = {Path, Headers, Data},
    do_aysnc_write(pick_worker(Client, Key), Request, ReplayFunAndArgs).

%%==============================================================================
%% Internal funcs
do_write(Worker, {_Path, _Headers, _Data} = Request) ->
    try ehttpc:request(Worker, post, Request) of
        {ok, 204, _} ->
            ok;
        {ok, 204, _, _} ->
            ok;
        {ok, StatusCode, Reason} ->
            {error, {StatusCode, Reason}};
        {ok, StatusCode, Reason, Body} ->
            {error, {StatusCode, Reason, Body}};
        Error ->
            {error, Error}
    catch E:R:S ->
        logger:error("[InfluxDB] http write fail: ~0p ~0p ~0p", [E, R, S]),
        {error, {E, R}}
    end.

do_aysnc_write(Worker, Request, ReplayFunAndArgs) ->
    ok = ehttpc:request_async(Worker, post, Request, 5000, ReplayFunAndArgs),
    {ok, Worker}.

pick_worker(#{pool := Pool, pool_type := hash}, Key) ->
    ehttpc_pool:pick_worker(Pool, Key);
pick_worker(#{pool := Pool}, _Key) ->
    ehttpc_pool:pick_worker(Pool).
