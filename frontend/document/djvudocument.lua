require "cache"
require "ui/geometry"

DjvuDocument = Document:new{
	_document = false,
	-- libdjvulibre manages its own additional cache, default value is hard written in c module.
	djvulibre_cache_size = nil,
	dc_null = DrawContext.new()
}

function DjvuDocument:init()
	local ok
	ok, self._document = pcall(djvu.openDocument, self.file, self.djvulibre_cache_size)
	if not ok then
		self.error_message = self.doc -- will contain error message
		return
	end
	self.is_open = true
	self.info.has_pages = true
	self:_readMetadata()
end

function DjvuDocument:_readMetadata()
	self.info.number_of_pages = self._document:getPages()
	return true
end

function DjvuDocument:close()
	if self.is_open then
		self.is_open = false
		self._document:close()
	end
end

function DjvuDocument:getNativePageDimensions(pageno)
	local hash = "pgdim|"..self.file.."|"..pageno
	local cached = Cache:check(hash)
	if cached then
		return cached[1]
	end
	local page = self._document:openPage(pageno)
	local page_size_w, page_size_h = page:getSize(self.dc_null)
	local page_size = Geom:new{ w = page_size_w, h = page_size_h }
	Cache:insert(hash, CacheItem:new{ page_size })
	page:close()
	return page_size
end

function DjvuDocument:getUsedBBox(pageno)
	--local hash = "pgubbox|"..self.file.."|"..pageno
	--local cached = Cache:check(hash)
	--if cached then
		--return cached.data
	--end
	--local page = self._document:openPage(pageno)
	local used = {}
	used.x, used.y, used.w, used.h = 0.01, 0.01, -0.01, -0.01
	--Cache:insert(hash, CacheItem:new{ used })
	--page:close()
	return used
end

function DjvuDocument:getPageText(pageno)
	-- is this worth caching? not done yet.
	local page = self._document:openPage(pageno)
	local text = page:getPageText()
	page:close()
	return text
end

function DjvuDocument:renderPage(pageno, rect, zoom, rotation)
	local hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation
	local page_size = self:getPageDimensions(pageno, zoom, rotation)
	-- this will be the size we actually render
	local size = page_size
	-- we prefer to render the full page, if it fits into cache
	if not Cache:willAccept(size.w * size.h / 2) then
		-- whole page won't fit into cache
		DEBUG("rendering only part of the page")
		-- TODO: figure out how to better segment the page
		if not rect then
			DEBUG("aborting, since we do not have a specification for that part")
			-- required part not given, so abort
			return
		end
		-- only render required part
		hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..tostring(rect)
		size = rect
	end

	-- prepare cache item with contained blitbuffer	
	local tile = CacheItem:new{
		size = size.w * size.h / 2 + 64, -- estimation
		excerpt = size,
		pageno = pageno,
		bb = Blitbuffer.new(size.w, size.h)
	}

	-- create a draw context
	local dc = DrawContext.new()

	dc:setRotate(rotation)
	-- correction of rotation
	if rotation == 90 then
		dc:setOffset(page_size.w, 0)
	elseif rotation == 180 then
		dc:setOffset(page_size.w, page_size.h)
	elseif rotation == 270 then
		dc:setOffset(0, page_size.h)
	end
	dc:setZoom(zoom)

	-- render
	local page = self._document:openPage(pageno)
	page:draw(dc, tile.bb, size.x, size.y)
	page:close()
	Cache:insert(hash, tile)

	return tile
end

-- a hint for the cache engine to paint a full page to the cache
-- TODO: this should trigger a background operation
function DjvuDocument:hintPage(pageno, zoom, rotation)
	self:renderPage(pageno, nil, zoom, rotation)
end

function DjvuDocument:drawPage(target, x, y, rect, pageno, zoom, rotation)
	local hash_full_page = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation
	local hash_excerpt = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..tostring(rect)
	local tile = Cache:check(hash_full_page)
	if not tile then
		tile = Cache:check(hash_excerpt)
		if not tile then
			DEBUG("rendering")
			tile = self:renderPage(pageno, rect, zoom, rotation)
		end
	end
	DEBUG("now painting", tile)
	target:blitFrom(tile.bb, x, y, rect.x - tile.excerpt.x, rect.y - tile.excerpt.y, rect.w, rect.h)
end

function DjvuDocument:invertTextYAxel(pageno, text_table)
	local _, height = self.doc:getOriginalPageSize(pageno)
	for _,text in pairs(text_table) do
		for _,line in ipairs(text) do
			line.y0, line.y1 = (height - line.y1), (height - line.y0)
		end
	end
	return text_table
end

DocumentRegistry:addProvider("djvu", "application/djvu", DjvuDocument)
