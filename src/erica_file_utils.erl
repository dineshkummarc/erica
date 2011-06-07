%%% -*- erlang -*-
%%%
%%% This file is part of erica released under the Apache 2 license.
%%% See the NOTICE for more information.

-module(erica_file_utils).

-export([rm_rf/1,
         cp_r/2,
         mv/2,
         delete_each/1]).

-include("erica.hrl").

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Remove files and directories.
%% Target is a single filename, directoryname or wildcard expression.
-spec rm_rf(Target::file:filename()) -> ok.
rm_rf(Target) ->
    case os:type() of
        {unix, _} ->
            {ok, []} = rebar_utils:sh(?FMT("rm -rf ~s", [Target]),
                                      [{use_stdout, false}, return_on_error]),
            ok;
        {win32, _} ->
            Filelist = filelib:wildcard(Target),
            Dirs = [F || F <- Filelist, filelib:is_dir(F)],
            Files = Filelist -- Dirs,
            ok = delete_each(Files),
            ok = delete_each_dir_win32(Dirs),
            ok
    end.

-spec cp_r(Sources::list(string()), Dest::file:filename()) -> ok.
cp_r(Sources, Dest) ->
    case os:type() of
        {unix, _} ->
            SourceStr = string:join(Sources, " "),
            {ok, []} = rebar_utils:sh(?FMT("cp -R ~s ~s", [SourceStr, Dest]),
                                      [{use_stdout, false}, return_on_error]),
            ok;
        {win32, _} ->
            lists:foreach(fun(Src) -> ok = cp_r_win32(Src,Dest) end, Sources),
            ok
    end.

-spec mv(Source::string(), Dest::file:filename()) -> ok.
mv(Source, Dest) ->
    case os:type() of
        {unix, _} ->
            {ok, []} = rebar_utils:sh(?FMT("mv ~s ~s", [Source, Dest]),
                                      [{use_stdout, false}, return_on_error]),
            ok;
        {win32, _} ->
            {ok, R} = rebar_utils:sh(
                        ?FMT("cmd " "/c move /y ~s ~s 1> nul",
                             [filename:nativename(Source),
                              filename:nativename(Dest)]),
                        [{use_stdout, false}, return_on_error]),
            case R of
                [] ->
                    ok;
                _ ->
                    {error, lists:flatten(
                              io_lib:format("Failed to move ~s to ~s~n",
                                            [Source, Dest]))}
            end
    end.

delete_each([]) ->
    ok;
delete_each([File | Rest]) ->
    case file:delete(File) of
        ok ->
            delete_each(Rest);
        {error, enoent} ->
            delete_each(Rest);
        {error, Reason} ->
            ?ERROR("Failed to delete file ~s: ~p\n", [File, Reason]),
            ?FAIL
    end.

%% ===================================================================
%% Internal functions
%% ===================================================================

delete_each_dir_win32([]) -> ok;
delete_each_dir_win32([Dir | Rest]) ->
    {ok, []} = rebar_utils:sh(?FMT("cmd /c rd /q /s ~s",
                                   [filename:nativename(Dir)]),
                              [{use_stdout, false}, return_on_error]),
    delete_each_dir_win32(Rest).

xcopy_win32(Source,Dest)->
    {ok, R} = rebar_utils:sh(
                ?FMT("cmd /c xcopy ~s ~s /q /y /e 2> nul",
                     [filename:nativename(Source), filename:nativename(Dest)]),
                [{use_stdout, false}, return_on_error]),
    case length(R) > 0 of
        %% when xcopy fails, stdout is empty and and error message is printed
        %% to stderr (which is redirected to nul)
        true -> ok;
        false ->
            {error, lists:flatten(
                      io_lib:format("Failed to xcopy from ~s to ~s~n",
                                    [Source, Dest]))}
    end.

cp_r_win32({true, SourceDir}, {true, DestDir}) ->
    %% from directory to directory
    SourceBase = filename:basename(SourceDir),
    ok = case file:make_dir(filename:join(DestDir, SourceBase)) of
             {error, eexist} -> ok;
             Other -> Other
         end,
    ok = xcopy_win32(SourceDir, filename:join(DestDir, SourceBase));
cp_r_win32({false, Source} = S,{true, DestDir}) ->
    %% from file to directory
    cp_r_win32(S, {false, filename:join(DestDir, filename:basename(Source))});
cp_r_win32({false, Source},{false, Dest}) ->
    %% from file to file
    {ok,_} = file:copy(Source, Dest),
    ok;
cp_r_win32(Source,Dest) ->
    Dst = {filelib:is_dir(Dest), Dest},
    lists:foreach(fun(Src) ->
                          ok = cp_r_win32({filelib:is_dir(Src), Src}, Dst)
                  end, filelib:wildcard(Source)),
    ok.
