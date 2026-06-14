module Main exposing (main)

{-| Browser map editor for the empire-builder game board.

The editor renders a movable viewport over a potentially large ASCII map, so the
DOM stays small no matter how big the map is. There are three layers stacked
bottom to top: base terrain, a resource layer, and a building layer. Palettes
come from the server (palette.json, resources.json, buildings.json); maps are
saved/loaded as JSON carrying every layer.

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



-- A keyed, colored glyph: terrain, resource, and building all share this shape.


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



-- MAP / GRID


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


rowsFromStrings : List String -> Array (Array Char)
rowsFromStrings rows =
    rows |> List.map (String.toList >> Array.fromList) |> Array.fromList


rowsToStrings : MapData -> List String
rowsToStrings m =
    m.rows |> Array.toList |> List.map (Array.toList >> String.fromList)



-- MODEL


type Tool
    = Paint
    | Fill
    | Eyedropper


type Layer
    = TerrainLayer
    | ResourceLayer
    | BuildingLayer


{-| An empty overlay cell (no resource / no building) is stored as a space.
-}
empty : Char
empty =
    ' '


type alias Snapshot =
    { terrain : MapData, resources : MapData, buildings : MapData }


type alias Model =
    { palette : List Terrain
    , byKey : Dict Char Terrain
    , resources : List Terrain
    , byResKey : Dict Char Terrain
    , buildings : List Terrain
    , byBldKey : Dict Char Terrain
    , map : MapData
    , resourceMap : MapData
    , buildingMap : MapData
    , name : String
    , tool : Tool
    , layer : Layer
    , active : Char
    , activeResource : Char
    , activeBuilding : Char
    , vx : Int
    , vy : Int
    , cursor : Maybe ( Int, Int )
    , history : List Snapshot
    , future : List Snapshot
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
      , resources = []
      , byResKey = Dict.empty
      , buildings = []
      , byBldKey = Dict.empty
      , map = makeMap 64 40 defaultFill
      , resourceMap = makeMap 64 40 empty
      , buildingMap = makeMap 64 40 empty
      , name = "untitled"
      , tool = Paint
      , layer = TerrainLayer
      , active = defaultFill
      , activeResource = empty
      , activeBuilding = empty
      , vx = 0
      , vy = 0
      , cursor = Nothing
      , history = []
      , future = []
      , status = "loading palettes…"
      , newW = "64"
      , newH = "40"
      , painting = False
      }
    , Cmd.batch
        [ Http.get { url = "palette.json", expect = Http.expectJson GotPalette (D.field "terrain" (D.list terrainDecoder)) }
        , Http.get { url = "resources.json", expect = Http.expectJson GotResources (D.field "resources" (D.list terrainDecoder)) }
        , Http.get { url = "buildings.json", expect = Http.expectJson GotBuildings (D.field "buildings" (D.list terrainDecoder)) }
        ]
    )



-- UPDATE


type Msg
    = GotPalette (Result Http.Error (List Terrain))
    | GotResources (Result Http.Error (List Terrain))
    | GotBuildings (Result Http.Error (List Terrain))
    | SelectTerrain Char
    | SelectResource Char
    | SelectBuilding Char
    | SetLayer Layer
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


byKeyOf : List Terrain -> Dict Char Terrain
byKeyOf list =
    list |> List.map (\t -> ( t.key, t )) |> Dict.fromList


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPalette (Ok terrains) ->
            let
                byKey =
                    byKeyOf terrains

                active =
                    if Dict.member model.active byKey then
                        model.active

                    else
                        List.head terrains |> Maybe.map .key |> Maybe.withDefault defaultFill
            in
            ( { model | palette = terrains, byKey = byKey, active = active, status = "ready" }, Cmd.none )

        GotPalette (Err _) ->
            ( { model | status = "could not load palette.json" }, Cmd.none )

        GotResources (Ok resources) ->
            ( { model | resources = resources, byResKey = byKeyOf resources, activeResource = firstKey resources }, Cmd.none )

        GotResources (Err _) ->
            ( { model | status = "could not load resources.json" }, Cmd.none )

        GotBuildings (Ok buildings) ->
            ( { model | buildings = buildings, byBldKey = byKeyOf buildings, activeBuilding = firstKey buildings }, Cmd.none )

        GotBuildings (Err _) ->
            ( { model | status = "could not load buildings.json" }, Cmd.none )

        SelectTerrain k ->
            ( { model | active = k, layer = TerrainLayer }, Cmd.none )

        SelectResource k ->
            ( { model | activeResource = k, layer = ResourceLayer }, Cmd.none )

        SelectBuilding k ->
            ( { model | activeBuilding = k, layer = BuildingLayer }, Cmd.none )

        SetLayer layer ->
            ( { model | layer = layer }, Cmd.none )

        SelectTool t ->
            ( { model | tool = t }, Cmd.none )

        CellMouseDown x y ->
            case model.tool of
                Eyedropper ->
                    ( eyedrop x y model, Cmd.none )

                Fill ->
                    ( setActiveGrid (floodFill x y (activeKey model) (activeGrid model)) (pushHistory model), Cmd.none )

                Paint ->
                    let
                        painted =
                            setActiveGrid (setCell x y (activeKey model) (activeGrid model)) (pushHistory model)
                    in
                    ( { painted | painting = True }, Cmd.none )

        CellMouseEnter x y ->
            let
                hovered =
                    { model | cursor = Just ( x, y ) }
            in
            if model.painting then
                ( setActiveGrid (setCell x y (activeKey hovered) (activeGrid hovered)) hovered, Cmd.none )

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

                pushed =
                    pushHistory model
            in
            ( { pushed | map = makeMap w h (grasslandKey model), resourceMap = makeMap w h empty, buildingMap = makeMap w h empty, vx = 0, vy = 0, status = "new map" }, Cmd.none )

        Undo ->
            case model.history of
                prev :: rest ->
                    ( restore prev { model | history = rest, future = current model :: model.future, status = "undo" }, Cmd.none )

                [] ->
                    ( { model | status = "nothing to undo" }, Cmd.none )

        Redo ->
            case model.future of
                next :: rest ->
                    ( restore next { model | future = rest, history = current model :: model.history, status = "redo" }, Cmd.none )

                [] ->
                    ( { model | status = "nothing to redo" }, Cmd.none )

        SaveMap ->
            ( { model | status = "saved " ++ model.name ++ ".json" }
            , Download.string (model.name ++ ".json") "application/json" (encodeMap model)
            )

        LoadRequested ->
            ( model, Select.file [ "application/json" ] FileSelected )

        FileSelected file ->
            ( { model | name = dropExtension (File.name file) }, Task.perform FileLoaded (File.toString file) )

        FileLoaded contents ->
            case D.decodeString mapDecoder contents of
                Ok loaded ->
                    ( { model | name = loaded.name, map = loaded.terrain, resourceMap = loaded.resources, buildingMap = loaded.buildings, history = [], future = [], vx = 0, vy = 0, status = "loaded " ++ loaded.name }, Cmd.none )

                Err _ ->
                    ( { model | status = "could not parse that map file" }, Cmd.none )


firstKey : List Terrain -> Char
firstKey list =
    List.head list |> Maybe.map .key |> Maybe.withDefault empty


current : Model -> Snapshot
current model =
    { terrain = model.map, resources = model.resourceMap, buildings = model.buildingMap }


restore : Snapshot -> Model -> Model
restore snap model =
    { model | map = snap.terrain, resourceMap = snap.resources, buildingMap = snap.buildings }


pushHistory : Model -> Model
pushHistory model =
    { model | history = current model :: model.history, future = [], status = "edited" }


activeGrid : Model -> MapData
activeGrid model =
    case model.layer of
        TerrainLayer ->
            model.map

        ResourceLayer ->
            model.resourceMap

        BuildingLayer ->
            model.buildingMap


setActiveGrid : MapData -> Model -> Model
setActiveGrid grid model =
    case model.layer of
        TerrainLayer ->
            { model | map = grid }

        ResourceLayer ->
            { model | resourceMap = grid }

        BuildingLayer ->
            { model | buildingMap = grid }


activeKey : Model -> Char
activeKey model =
    case model.layer of
        TerrainLayer ->
            model.active

        ResourceLayer ->
            model.activeResource

        BuildingLayer ->
            model.activeBuilding


eyedrop : Int -> Int -> Model -> Model
eyedrop x y model =
    let
        picked =
            getCell x y (activeGrid model) |> Maybe.withDefault (activeKey model)
    in
    case model.layer of
        TerrainLayer ->
            { model | active = picked }

        ResourceLayer ->
            { model | activeResource = picked }

        BuildingLayer ->
            { model | activeBuilding = picked }


dropExtension : String -> String
dropExtension s =
    case String.split "." s of
        [ single ] ->
            single

        parts ->
            parts |> List.take (List.length parts - 1) |> String.join "."



-- ENCODE / DECODE


encodeMap : Model -> String
encodeMap model =
    E.encode 2 <|
        E.object
            [ ( "name", E.string model.name )
            , ( "width", E.int model.map.width )
            , ( "height", E.int model.map.height )
            , ( "rows", E.list E.string (rowsToStrings model.map) )
            , ( "resources", E.list E.string (rowsToStrings model.resourceMap) )
            , ( "buildings", E.list E.string (rowsToStrings model.buildingMap) )
            ]


type alias LoadedMap =
    { name : String, terrain : MapData, resources : MapData, buildings : MapData }


mapDecoder : D.Decoder LoadedMap
mapDecoder =
    D.map6
        (\name w h rows mres mbld ->
            { name = name
            , terrain = { width = w, height = h, rows = rowsFromStrings rows }
            , resources = overlayGrid w h mres
            , buildings = overlayGrid w h mbld
            }
        )
        (D.field "name" D.string)
        (D.field "width" D.int)
        (D.field "height" D.int)
        (D.field "rows" (D.list D.string))
        (D.maybe (D.field "resources" (D.list D.string)))
        (D.maybe (D.field "buildings" (D.list D.string)))


overlayGrid : Int -> Int -> Maybe (List String) -> MapData
overlayGrid w h rows =
    case rows of
        Just rr ->
            { width = w, height = h, rows = rowsFromStrings rr }

        Nothing ->
            makeMap w h empty



-- VIEW


view : Model -> Html Msg
view model =
    div [ A.style "font-family" "monospace", A.style "background" "#0f1115", A.style "color" "#ddd", A.style "min-height" "100vh", A.style "padding" "8px" ]
        [ div [ A.style "display" "flex", A.style "gap" "16px", A.style "flex-wrap" "wrap", A.style "align-items" "flex-start" ]
            [ layerView model
            , paletteView model
            , toolsView model
            ]
        , gridView model
        , statusView model
        ]


layerView : Model -> Html Msg
layerView model =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "layer" ]
        , div [ A.style "display" "flex", A.style "gap" "4px" ]
            [ layerButton model TerrainLayer "terrain"
            , layerButton model ResourceLayer "resources"
            , layerButton model BuildingLayer "buildings"
            ]
        ]


layerButton : Model -> Layer -> String -> Html Msg
layerButton model layer label =
    button
        [ onClick (SetLayer layer)
        , A.style "background" (highlightIf (model.layer == layer))
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        ]
        [ text label ]


paletteView : Model -> Html Msg
paletteView model =
    case model.layer of
        TerrainLayer ->
            paletteSection "terrain" (List.map (paletteButton SelectTerrain model.active) model.palette)

        ResourceLayer ->
            paletteSection "resources" (noneButton SelectResource model.activeResource :: List.map (paletteButton SelectResource model.activeResource) model.resources)

        BuildingLayer ->
            paletteSection "buildings" (noneButton SelectBuilding model.activeBuilding :: List.map (paletteButton SelectBuilding model.activeBuilding) model.buildings)


paletteSection : String -> List (Html Msg) -> Html Msg
paletteSection label buttons =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text label ]
        , div [ A.style "display" "flex", A.style "flex-wrap" "wrap", A.style "max-width" "360px", A.style "gap" "4px" ] buttons
        ]


paletteButton : (Char -> Msg) -> Char -> Terrain -> Html Msg
paletteButton toMsg activeK t =
    button
        [ onClick (toMsg t.key)
        , A.style "background" (highlightIf (t.key == activeK))
        , A.style "color" (cssColor t.color)
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 6px"
        , A.style "cursor" "pointer"
        , A.style "font-family" "monospace"
        ]
        [ text (t.glyph ++ " " ++ t.id) ]


noneButton : (Char -> Msg) -> Char -> Html Msg
noneButton toMsg activeK =
    button
        [ onClick (toMsg empty)
        , A.style "background" (highlightIf (activeK == empty))
        , A.style "color" "#aaa"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 6px"
        , A.style "cursor" "pointer"
        ]
        [ text "· none (erase)" ]


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
            , editorLink "/terrain.html" "edit terrain ↗"
            , editorLink "/resources.html" "edit resources ↗"
            , editorLink "/buildings.html" "edit buildings ↗"
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
        , A.style "background" (highlightIf (t == model.tool))
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


editorLink : String -> String -> Html Msg
editorLink href label =
    a
        [ A.href href
        , A.target "_blank"
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "text-decoration" "none"
        ]
        [ text label ]


highlightIf : Bool -> String
highlightIf on =
    if on then
        "#2b3550"

    else
        "#1a1d24"


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
        ( glyph, color ) =
            topCell model x y

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


{-| The glyph drawn at a tile: building over resource over terrain.
-}
topCell : Model -> Int -> Int -> ( String, String )
topCell model x y =
    case overlayAt x y model.buildingMap model.byBldKey of
        Just gc ->
            gc

        Nothing ->
            case overlayAt x y model.resourceMap model.byResKey of
                Just gc ->
                    gc

                Nothing ->
                    let
                        terrainCh =
                            getCell x y model.map |> Maybe.withDefault ' '
                    in
                    case Dict.get terrainCh model.byKey of
                        Just t ->
                            ( t.glyph, cssColor t.color )

                        Nothing ->
                            ( String.fromChar terrainCh, "#888" )


overlayAt : Int -> Int -> MapData -> Dict Char Terrain -> Maybe ( String, String )
overlayAt x y grid dict =
    let
        ch =
            getCell x y grid |> Maybe.withDefault empty
    in
    if ch == empty then
        Nothing

    else
        Dict.get ch dict |> Maybe.map (\t -> ( t.glyph, cssColor t.color ))


statusView : Model -> Html Msg
statusView model =
    let
        cursorText =
            case model.cursor of
                Just ( x, y ) ->
                    String.fromInt x ++ "," ++ String.fromInt y

                Nothing ->
                    "—"

        layerText =
            case model.layer of
                TerrainLayer ->
                    "terrain:" ++ nameOf model.active model.byKey

                ResourceLayer ->
                    "resource:" ++ overlayName model.activeResource model.byResKey

                BuildingLayer ->
                    "building:" ++ overlayName model.activeBuilding model.byBldKey
    in
    div [ A.style "margin-top" "8px", A.style "opacity" "0.85" ]
        [ text
            (String.join "  ·  "
                [ model.name ++ " (" ++ String.fromInt model.map.width ++ "×" ++ String.fromInt model.map.height ++ ")"
                , "cursor " ++ cursorText
                , "view " ++ String.fromInt model.vx ++ "," ++ String.fromInt model.vy
                , layerText
                , model.status
                ]
            )
        ]


nameOf : Char -> Dict Char Terrain -> String
nameOf k dict =
    Dict.get k dict |> Maybe.map .id |> Maybe.withDefault (String.fromChar k)


overlayName : Char -> Dict Char Terrain -> String
overlayName k dict =
    if k == empty then
        "none"

    else
        nameOf k dict


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
