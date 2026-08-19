-- RfsAimCore.lua — VOLATILE stub. Creation-mounted aiming brain (mesh + wiring only).
-- Logic parents switch commands later (GUI later). Logic children = on-target later.
-- Bearings as children later. No targeting / chase / shoot. Idle = no drain.
-- Never parent FX / ShapeRenderable / lights onto this interactable.

RfsAimCore = class( nil )
RfsAimCore.maxParentCount = 255
RfsAimCore.maxChildCount = 255
RfsAimCore.connectionInput = sm.interactable.connectionType.logic
RfsAimCore.connectionOutput = sm.interactable.connectionType.logic
RfsAimCore.colorNormal = sm.color.new( 0x6b7d8aff )
RfsAimCore.colorHighlight = sm.color.new( 0x9aabb8ff )
RfsAimCore.connectIcon = "logic"

local LOGIC = sm.interactable.connectionType.logic

local function band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a % ( b * 2 ) >= b and b or 0
end

function RfsAimCore.server_onCreate( self )
	pcall( function()
		self.interactable:setActive( false )
	end )
end

function RfsAimCore.client_getAvailableParentConnectionCount( self, connectionType )
	if band( connectionType, LOGIC ) ~= 0 then
		return 255
	end
	return 0
end

function RfsAimCore.client_getAvailableChildConnectionCount( self, connectionType )
	if band( connectionType, LOGIC ) ~= 0 then
		return 255
	end
	return 0
end
