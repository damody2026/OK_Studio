package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local root='C:/portable/OpenKoikatsu';local o=root..'/output/street-social-city-production/motel-decor-tripo-v1'
local function read(p)local f=assert(io.open(p,'rb'));local r=j.decode(f:read('*a'));f:close();return r end
local pairs_text=[=[
gilded bronze acanthus urn with ivory body burgundy medallions and swan handles|ornate mantel clock with burgundy enamel gilt scrollwork and ivory Roman dial
golden geometric falcon sculpture on black marble plinth with turquoise inlays|pierced brass Arabian lantern with cobalt glass and onion dome
engraved silver Arabic coffee dallah with long curved spout and turquoise enamel|ornate hexagonal inlaid marquetry incense burner with brass lattice lid
carved black basalt Egyptian feline statue with lapis and gold collar|turquoise faience lotus vessel with golden scarab feet
vintage brass cinema film projector with twin reels and mahogany base|art deco gilded theatre mask sculpture on black stone stand
red lacquer miniature Parisian windmill sculpture with brass blades|cabaret feather fan in carved bronze stand with crimson velvet and pearls
deep blue celestial globe with bronze zodiac meridian and star inlays|golden crescent moon sculpture holding a suspended cobalt crystal star
iridescent folded ribbon sculpture on polished white marble base|asymmetric black porcelain vase with gold fine-line chevrons
vintage graffiti painted boombox sculpture with realistic metal speakers|gold plated sculptural sneaker trophy on charcoal plinth no logos
glossy crimson interlocking abstract lips ceramic sculpture on black base|art deco pink glass perfume bottle with faceted crystal stopper
brushed steel Manhattan skyline sculpture mounted on smoked stone plinth|art deco smoky glass cocktail shaker with fluted silver bands
hand carved Balinese sandstone temple dancer relief on standing teak frame|woven rattan lidded offering basket with carved frangipani finial
hand carved koa wood sea turtle sculpture on lava rock plinth|aged Hawaiian ceramic pineapple vessel with green glazed crown
lavender bouquet in rustic mauve ceramic jug with woven ribbon|weathered cream French country birdcage with tiny bronze birds
ivory porcelain swan bowl with gold feather detailing|gilded rococo oval tabletop picture frame with painted floral medallion
sculptural bamboo ikebana vase with pebble base and single plum branch|hand hewn dark stone tea tray holding jade cup and bamboo tea whisk
iridescent mother of pearl nautilus shell sculpture on silver seaweed base|deep blue art glass wave sculpture with frosted white crest
pink porcelain peony blossom arrangement with bronze stems|hand painted floral ceramic garden urn with sculpted butterfly handles
black and white zebra striped sculptural ceramic ring vase|rose gold geometric butterfly sculpture on black marble pedestal
burgundy velvet lined gilded jewelry casket with carved rose lid|bronze intertwined heart sculpture with dark red glass inset
layered sand toned ceramic vase with wide horizontal ribbing|stacked limestone pebble sculpture with brushed brass connecting pin
warm ivory sculptural ceramic table bowl with walnut foot|small walnut mantel sculpture depicting embracing abstract forms
white coral branch sculpture mounted on weathered limestone block|aqua blown glass sea anemone vessel with pearl rim
hammered copper lotus bowl on dark basalt stand|turquoise ceramic amphora with silver wave handles
polished obsidian manta ray sculpture with silver edging|cobalt glass sea horse sculpture on black stone base
cream limestone shell bowl with carved spiral and green patina bronze foot|sunburst gold tropical leaf sculpture on white stone pedestal
pastel pink candy jar sculpture with striped ceramic lid and candy cane handles|sculptural mint green cupcake box with gold trim and cherry finial
oversized black and gold spade sculpture with faceted mirror inlay|ruby glass chess queen sculpture mounted on checkered stone plinth
hammered brass hammam bath ewer with engraved floral body|turquoise Iznik ceramic bowl with raised tulip relief and brass tripod
lunar crater sphere sculpture on brushed steel crescent cradle|small retro space lander sculpture with gold foil panels and dark windows
large blue morpho butterfly sculpture with bronze openwork wings|pink and gold porcelain orchid branch in lacquered black vase
whimsical white rabbit clock sculpture with blue waistcoat and brass details|oversized lavender teapot sculpture with vine shaped handle and porcelain roses
art deco bronze dancing silhouette sculpture with flowing red skirt|black lacquer miniature stage drum with crimson feather finial
ivory ceramic angel wing pair sculpture joined at bronze heart base|pearl white dove sculpture perched on sculpted gilt olive branch
Balinese carved teak frangipani vase with cream stone flower bouquet|dark volcanic stone guardian bird sculpture with turquoise eyes
glazed sunset orange tropical hibiscus bowl with lava black foot|carved mango wood outrigger canoe sculpture on a low plinth
quilted black porcelain vanity box with pearl white camellia lid no logos|sculptural gold interlocking oval loops mounted on white marble
bold blue and gold baroque ceramic urn with sculpted ram handles no logos|gilded sun face wall medallion on a solid black tabletop easel
hand carved Balinese lotus candle holder in aged white stone|woven pandan decorative storage jar with sculpted bronze dragonfly lid
sun bleached driftwood pelican sculpture with pale blue accents|warm amber art glass sun sculpture on travertine pedestal
vintage Shanghai jade and brass gramophone with dark rosewood base|red lacquer pagoda jewelry chest with inlaid mother of pearl blossom
smoky amethyst crystal cluster sculpture with gold geological seams|clear faceted crystal obelisk rising from sculpted silver leaf base
hand painted Mediterranean blue and white ceramic amphora|weathered ivory ceramic lighthouse sculpture with cobalt balcony
rose pink ceramic high heel sculpture with pearl trim no logos|glossy blush porcelain bow shaped lidded keepsake box with gold feet
gilded baroque violin scroll sculpture with ivory floral carvings|burgundy and gold rococo perfume bottle with oversized acanthus stopper
ivory Tudor rose relief sculpture on carved walnut stand|antique silver crown shaped trinket bowl with dark blue enamel
matte black twisted ceramic vase with gilded interior|black marble abstract musical spiral sculpture with polished silver edge
celadon porcelain moon flask with raised pearl dragon motif|lacquered ebony folding fan sculpture with gold cherry blossom relief
aged bronze garden bird bath miniature with trailing ivy|moss glazed ceramic secret garden gate sculpture on stone base
carved walnut owl sculpture nestled in a twisting root base|amber resin forest mushroom cluster mounted on weathered wood
platinum finished geometric crystal tree sculpture on dark stone plinth|silver faceted dodecahedron keepsake box with smoked crystal panels
five interlocking translucent colored glass elemental rings on graphite base|futuristic copper and teal kinetic orb sculpture with sturdy solid supports
antique rose painted French porcelain perfume atomizer with pearlescent bulb|distressed mauve ceramic rose wreath sculpture on cream pedestal
miniature Venetian gondola music box in polished ebony with gilt detailing|sculptural bronze treble clef framed by Murano inspired blue glass ribbons
vintage turquoise American fuel pump tabletop sculpture no text no brands|weathered red and cream classic roadster sculpture on dark walnut base
art deco brass skyscraper bookend sculpture with green marble base|smoky amber geometric glass perfume decanter with silver stepped cap
deep purple velvet jewelry chest with carved ivory Tudor rose lid|antique brass miniature throne sculpture with lavender enamel back
black porcelain raven sculpture with dark purple iridescent feather glaze|black and silver art deco stepped candle holder with amethyst glass cup
polished chrome abstract city skyline on black granite base|deep emerald art glass faceted vase with brass collar
white porcelain pearl dragon sculpture coiled around jade sphere|red and gold lacquer lotus keepsake vessel with carved ebony lid
bronze angel feather sculpture rising from polished white marble|ivory cherub relief medallion inside a gilded freestanding oval frame
]=]
local rooms=read(root..'/output/street-social-city-production/motel-v1/motel-plan.json').rooms;local rows={};local i=0
for line in pairs_text:gmatch('[^\r\n]+')do i=i+1;local a,b=line:match('^(.-)|(.-)$');assert(a and b);local r=assert(rooms[i]);for k,d in ipairs({a,b})do local suffix=k==1 and 'A'or'B';rows[#rows+1]={id=r.id..'-decor-'..suffix,room_id=r.id,building=r.building,room_number=r.room_number,source_name=r.source_name,reference_url=r.reference_url,design_observations=r.design_observations,slot=suffix,description=d,status='planned',prompt='One realistic luxury hotel decorative object: '..d..'. Exclusive ornament '..suffix..' for Yinghui motel '..r.building..' room'..r.room_number..' themed '..r.source_name..'. Entire isolated freestanding object with a stable closed base. Physically plausible sculptural craftsmanship, rich detailed PBR materials, game-ready mesh. No room, no scenery, no floor, no people, no text, no logos. Distinct silhouette, not a flat image.'}end end
assert(i==61 and #rows==122);local f=assert(io.open(o..'/plan.json','wb'));f:write(j.encode({status='planned_requires_actual_tripo_generation_and_download',rooms=61,required_assets=122,source='Official room catalogue and audited motel-plan room mapping',assets=rows}));f:close();print('Planned122 unique ornaments for61 rooms')
