module Main exposing (main)

{-| Browser map editor for the empire-builder game board.

The editor renders a movable viewport over a potentially large ASCII map, so the
DOM stays small no matter how big the map is. Terrain comes from the palette the
server emits (palette.json); maps are saved and loaded as JSON files.

-}

import Array exposing (Array)
import Browser
import Browser.Events
import Dict exposing (Dict)
import File exposing (File)
import File.Download as Download
import File.Select as Select
import Html exposing (Html, a, button, div, input, span, text)
import Html.Attributes as A
import Html.Events exposing (onClick, onInput, onMouseDown, onMouseEnter)
import Http
import Json.Decode as D
import Json.Encode as E
import Task



-- TERRAIN


type alias Terrain =
    { id : String
    , key : Char
    , glyph : String
    , color : String
    }


terrainDecoder : D.Decoder Terrain
terrainDecoder =
    D.map4 Terrain
        (D.field "id" D.string)
        (D.field "key" (D.string |> D.map firstChar))
        (D.field "glyph" D.string)
        (D.field "color" D.string)


firstChar : String -> Char
firstChar s =
    String.uncons s |> Maybe.map Tuple.first |> Maybe.withDefault ' '



-- MAP


type alias MapData =
    { width : Int
    , height : Int
    , rows : Array (Array Char)
    }


makeMap : Int -> Int -> Char -> MapData
makeMap w h fill =
    { width = w
    , height = h
    , rows = Array.repeat h (Array.repeat w fill)
    }


getCell : Int -> Int -> MapData -> Maybe Char
getCell x y m =
    Array.get y m.rows |> Maybe.andThen (Array.get x)


setCell : Int -> Int -> Char -> MapData -> MapData
setCell x y c m =
    case Array.get y m.rows of
        Just row ->
            { m | rows = Array.set y (Array.set x c row) m.rows }

        Nothing ->
            m


floodFill : Int -> Int -> Char -> MapData -> MapData
floodFill x y replacement m =
    case getCell x y m of
        Just target ->
            if target == replacement then
                m

            else
                floodLoop replacement target [ ( x, y ) ] m

        Nothing ->
            m


floodLoop : Char -> Char -> List ( Int, Int ) -> MapData -> MapData
floodLoop replacement target stack m =
    case stack of
        [] ->
            m

        ( cx, cy ) :: rest ->
            if getCell cx cy m == Just target then
                floodLoop replacement
                    target
                    (( cx - 1, cy ) :: ( cx + 1, cy ) :: ( cx, cy - 1 ) :: ( cx, cy + 1 ) :: rest)
                    (setCell cx cy replacement m)

            else
                floodLoop replacement target rest m


mapDecoder : D.Decoder ( String, MapData )
mapDecoder =
    D.map4 (\name w h rows -> ( name, { width = w, height = h, rows = rowsFromStrings rows } ))
        (D.field "name" D.string)
        (D.field "width" D.int)
        (D.field "height" D.int)
        (D.field "rows" (D.list D.string))


rowsFromStrings : List String -> Array (Array Char)
rowsFromStrings rows =
    rows |> List.map (String.toList >> Array.fromList) |> Array.fromList


encodeMap : String -> MapData -> String
encodeMap name m =
    E.encode 2 <|
        E.object
            [ ( "name", E.string name )
            , ( "width", E.int m.width )
            , ( "height", E.int m.height )
            , ( "rows"
              , E.list E.string
                    (m.rows |> Array.toList |> List.map (Array.toList >> String.fromList))
              )
            ]



-- MODEL


type Tool
    = Paint
    | Fill
    | Eyedropper


type alias Model =
    { palette : List Terrain
    , byKey : Dict Char Terrain
    , map : MapData
    , name : String
    , tool : Tool
    , active : Char
    , vx : Int
    , vy : Int
    , cursor : Maybe ( Int, Int )
    , history : List MapData
    , future : List MapData
    , status : String
    , newW : String
    , newH : String
    , painting : Bool
    }


viewportW : Int
viewportW =
    72


viewportH : Int
viewportH =
    36


defaultFill : Char
defaultFill =
    'g'


grasslandKey : Model -> Char
grasslandKey model =
    model.palette
        |> List.filter (\t -> t.id == "grassland")
        |> List.head
        |> Maybe.map .key
        |> Maybe.withDefault defaultFill


init : () -> ( Model, Cmd Msg )
init _ =
    ( { palette = []
      , byKey = Dict.empty
      , map = makeMap 64 40 defaultFill
      , name = "untitled"
      , tool = Paint
      , active = defaultFill
      , vx = 0
      , vy = 0
      , cursor = Nothing
      , history = []
      , future = []
      , status = "loading palette…"
      , newW = "64"
      , newH = "40"
      , painting = False
      }
    , Http.get { url = "palette.json", expect = Http.expectJson GotPalette (D.field "terrain" (D.list terrainDecoder)) }
    )



-- UPDATE


type Msg
    = GotPalette (Result Http.Error (List Terrain))
    | SelectTerrain Char
    | SelectTool Tool
    | CellMouseDown Int Int
    | CellMouseEnter Int Int
    | StopPaint
    | Pan Int Int
    | SetNewW String
    | SetNewH String
    | NewMap
    | Undo
    | Redo
    | SaveMap
    | LoadRequested
    | FileSelected File
    | FileLoaded String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPalette (Ok terrains) ->
            let
                byKey =
                    terrains |> List.map (\t -> ( t.key, t )) |> Dict.fromList

                active =
                    if Dict.member model.active byKey then
                        model.active

                    else
                        List.head terrains |> Maybe.map .key |> Maybe.withDefault defaultFill
            in
            ( { model | palette = terrains, byKey = byKey, active = active, status = "ready" }, Cmd.none )

        GotPalette (Err _) ->
            ( { model | status = "could not load palette.json" }, Cmd.none )

        SelectTerrain k ->
            ( { model | active = k }, Cmd.none )

        SelectTool t ->
            ( { model | tool = t }, Cmd.none )

        CellMouseDown x y ->
            case model.tool of
                Eyedropper ->
                    ( { model | active = getCell x y model.map |> Maybe.withDefault model.active }, Cmd.none )

                Fill ->
                    ( commit (floodFill x y model.active model.map) model, Cmd.none )

                Paint ->
                    let
                        started =
                            { model | history = model.map :: model.history, future = [], painting = True, status = "edited" }
                    in
                    ( { started | map = setCell x y model.active started.map }, Cmd.none )

        CellMouseEnter x y ->
            let
                hovered =
                    { model | cursor = Just ( x, y ) }
            in
            if model.painting then
                ( { hovered | map = setCell x y model.active hovered.map }, Cmd.none )

            else
                ( hovered, Cmd.none )

        StopPaint ->
            ( { model | painting = False }, Cmd.none )

        Pan dx dy ->
            ( { model
                | vx = clamp 0 (max 0 (model.map.width - 1)) (model.vx + dx)
                , vy = clamp 0 (max 0 (model.map.height - 1)) (model.vy + dy)
              }
            , Cmd.none
            )

        SetNewW s ->
            ( { model | newW = s }, Cmd.none )

        SetNewH s ->
            ( { model | newH = s }, Cmd.none )

        NewMap ->
            let
                w =
                    String.toInt model.newW |> Maybe.withDefault 64 |> clamp 1 1000

                h =
                    String.toInt model.newH |> Maybe.withDefault 40 |> clamp 1 1000
            in
            ( commit (makeMap w h (grasslandKey model)) { model | vx = 0, vy = 0 }, Cmd.none )

        Undo ->
            case model.history of
                prev :: rest ->
                    ( { model | map = prev, history = rest, future = model.map :: model.future, status = "undo" }, Cmd.none )

                [] ->
                    ( { model | status = "nothing to undo" }, Cmd.none )

        Redo ->
            case model.future of
                next :: rest ->
                    ( { model | map = next, future = rest, history = model.map :: model.history, status = "redo" }, Cmd.none )

                [] ->
                    ( { model | status = "nothing to redo" }, Cmd.none )

        SaveMap ->
            ( { model | status = "saved " ++ model.name ++ ".json" }
            , Download.string (model.name ++ ".json") "application/json" (encodeMap model.name model.map)
            )

        LoadRequested ->
            ( model, Select.file [ "application/json" ] FileSelected )

        FileSelected file ->
            ( { model | name = dropExtension (File.name file) }, Task.perform FileLoaded (File.toString file) )

        FileLoaded contents ->
            case D.decodeString mapDecoder contents of
                Ok ( name, m ) ->
                    ( commit m { model | name = name, vx = 0, vy = 0, status = "loaded " ++ name }, Cmd.none )

                Err _ ->
                    ( { model | status = "could not parse that map file" }, Cmd.none )


{-| Apply a new map, pushing the prior one onto the undo history.
-}
commit : MapData -> Model -> Model
commit newMap model =
    { model | map = newMap, history = model.map :: model.history, future = [], status = "edited" }


dropExtension : String -> String
dropExtension s =
    case String.split "." s of
        [ single ] ->
            single

        parts ->
            parts |> List.take (List.length parts - 1) |> String.join "."



-- VIEW


view : Model -> Html Msg
view model =
    div [ A.style "font-family" "monospace", A.style "background" "#0f1115", A.style "color" "#ddd", A.style "min-height" "100vh", A.style "padding" "8px" ]
        [ div [ A.style "display" "flex", A.style "gap" "16px", A.style "flex-wrap" "wrap", A.style "align-items" "flex-start" ]
            [ paletteView model
            , toolsView model
            ]
        , gridView model
        , statusView model
        ]


paletteView : Model -> Html Msg
paletteView model =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "terrain" ]
        , div [ A.style "display" "flex", A.style "flex-wrap" "wrap", A.style "max-width" "360px", A.style "gap" "4px" ]
            (List.map (terrainButton model) model.palette)
        ]


terrainButton : Model -> Terrain -> Html Msg
terrainButton model t =
    button
        [ onClick (SelectTerrain t.key)
        , A.style "background"
            (if t.key == model.active then
                "#2b3550"

             else
                "#1a1d24"
            )
        , A.style "color" (cssColor t.color)
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 6px"
        , A.style "cursor" "pointer"
        , A.style "font-family" "monospace"
        ]
        [ text (t.glyph ++ " " ++ t.id) ]


toolsView : Model -> Html Msg
toolsView model =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "tools" ]
        , div [ A.style "display" "flex", A.style "gap" "4px", A.style "flex-wrap" "wrap" ]
            [ toolButton model Paint "paint"
            , toolButton model Fill "fill"
            , toolButton model Eyedropper "pick"
            , plainButton Undo "undo"
            , plainButton Redo "redo"
            , plainButton SaveMap "save"
            , plainButton LoadRequested "load"
            , terrainEditorLink
            ]
        , div [ A.style "margin-top" "8px", A.style "display" "flex", A.style "gap" "4px", A.style "align-items" "center" ]
            [ text "new "
            , sizeInput model.newW SetNewW
            , text "×"
            , sizeInput model.newH SetNewH
            , plainButton NewMap "create"
            ]
        , div [ A.style "margin-top" "8px", A.style "display" "flex", A.style "gap" "4px" ]
            [ plainButton (Pan -16 0) "◀"
            , plainButton (Pan 16 0) "▶"
            , plainButton (Pan 0 -8) "▲"
            , plainButton (Pan 0 8) "▼"
            ]
        ]


toolButton : Model -> Tool -> String -> Html Msg
toolButton model t label =
    button
        [ onClick (SelectTool t)
        , A.style "background"
            (if t == model.tool then
                "#2b3550"

             else
                "#1a1d24"
            )
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        ]
        [ text label ]


plainButton : Msg -> String -> Html Msg
plainButton msg label =
    button
        [ onClick msg
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        ]
        [ text label ]


terrainEditorLink : Html Msg
terrainEditorLink =
    a
        [ A.href "/terrain.html"
        , A.target "_blank"
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "text-decoration" "none"
        ]
        [ text "edit terrain ↗" ]


sizeInput : String -> (String -> Msg) -> Html Msg
sizeInput val toMsg =
    input
        [ A.value val
        , onInput toMsg
        , A.style "width" "48px"
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        ]
        []


gridView : Model -> Html Msg
gridView model =
    let
        rows =
            List.range model.vy (min (model.vy + viewportH - 1) (model.map.height - 1))
    in
    div
        [ A.style "margin-top" "10px"
        , A.style "line-height" "1.05"
        , A.style "font-size" "16px"
        , A.style "background" "#000"
        , A.style "padding" "6px"
        , A.style "display" "inline-block"
        , A.style "border" "1px solid #222"
        , A.style "user-select" "none"
        ]
        (List.map (rowView model) rows)


rowView : Model -> Int -> Html Msg
rowView model y =
    let
        cols =
            List.range model.vx (min (model.vx + viewportW - 1) (model.map.width - 1))
    in
    div [ A.style "white-space" "pre" ] (List.map (\x -> cellView model x y) cols)


cellView : Model -> Int -> Int -> Html Msg
cellView model x y =
    let
        ch =
            getCell x y model.map |> Maybe.withDefault ' '

        terrain =
            Dict.get ch model.byKey

        glyph =
            terrain |> Maybe.map .glyph |> Maybe.withDefault (String.fromChar ch)

        color =
            terrain |> Maybe.map (.color >> cssColor) |> Maybe.withDefault "#888"

        highlight =
            model.cursor == Just ( x, y )
    in
    span
        [ onMouseEnter (CellMouseEnter x y)
        , onMouseDown (CellMouseDown x y)
        , A.style "color" color
        , A.style "display" "inline-block"
        , A.style "width" "1ch"
        , A.style "background"
            (if highlight then
                "#444"

             else
                "transparent"
            )
        ]
        [ text glyph ]


statusView : Model -> Html Msg
statusView model =
    let
        cursorText =
            case model.cursor of
                Just ( x, y ) ->
                    String.fromInt x ++ "," ++ String.fromInt y

                Nothing ->
                    "—"

        activeName =
            Dict.get model.active model.byKey |> Maybe.map .id |> Maybe.withDefault (String.fromChar model.active)
    in
    div [ A.style "margin-top" "8px", A.style "opacity" "0.85" ]
        [ text
            (String.join "  ·  "
                [ model.name ++ " (" ++ String.fromInt model.map.width ++ "×" ++ String.fromInt model.map.height ++ ")"
                , "cursor " ++ cursorText
                , "view " ++ String.fromInt model.vx ++ "," ++ String.fromInt model.vy
                , "terrain " ++ activeName
                , model.status
                ]
            )
        ]


cssColor : String -> String
cssColor name =
    case name of
        "black" ->
            "#1b1b1b"

        "red" ->
            "#d35f5f"

        "green" ->
            "#3c9a4e"

        "yellow" ->
            "#c9b458"

        "blue" ->
            "#3a78c2"

        "magenta" ->
            "#b05fb0"

        "cyan" ->
            "#4dd0e1"

        "white" ->
            "#cfcfcf"

        "bright_black" ->
            "#7a7a7a"

        "bright_red" ->
            "#ff6b6b"

        "bright_green" ->
            "#8bc34a"

        "bright_yellow" ->
            "#e6c84f"

        "bright_blue" ->
            "#5b9be0"

        "bright_magenta" ->
            "#e07be0"

        "bright_cyan" ->
            "#7fe7f3"

        "bright_white" ->
            "#ffffff"

        _ ->
            "#aaaaaa"



-- MAIN


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.painting then
        Browser.Events.onMouseUp (D.succeed StopPaint)

    else
        Sub.none


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
