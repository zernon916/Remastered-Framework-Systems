-- RfsMapLock.lua - invisible lock part for /map top-down camera
-- Author: DemonsDen126
-- Top-down map lock -> continuous cutsceneTP camera.

RfsMapLock = class()

RfsMapLock.moveSpeed = 35
RfsMapLock.zoomSpeed = 48
RfsMapLock.mapHeight = 1200

function RfsMapLock.server_onCreate( self )
	self.sv = { owner = nil, closing = false }
	print( "[RFS] /map lock part server_onCreate" )
end

function RfsMapLock.server_onDestroy( self )
	if self.sv and self.sv.closing then
		return
	end
	if self.sv and self.sv.owner and sm.exists( self.sv.owner ) then
		pcall( function()
			sm.event.sendToPlayer( self.sv.owner, "sv_rfs_mapPartDestroyed" )
		end )
	end
end

function RfsMapLock.sv_n_setOwner( self, params )
	local player = params and params.player
	if not player or not sm.exists( player ) then
		print( "[RFS] /map setOwner failed: bad player" )
		return
	end
	self.sv.owner = player
	local payload = {
		player = player,
		x = params.x,
		y = params.y,
		height = params.height or self.mapHeight,
		zoom = params.zoom or 200
	}
	self.network:sendToClient( player, "cl_n_begin", payload )
	print( "[RFS] /map lock owner set -> cl_n_begin" )
end

function RfsMapLock.sv_n_requestClose( self, _, player )
	self.sv.closing = true
	local owner = ( self.sv and self.sv.owner ) or player
	if owner and sm.exists( owner ) then
		sm.event.sendToPlayer( owner, "sv_rfs_mapClose" )
	elseif self.shape and sm.exists( self.shape ) then
		self.shape:destroyShape( 0 )
	end
end

function RfsMapLock.sv_n_markClosing( self )
	if self.sv then
		self.sv.closing = true
		self.sv.owner = nil
	end
end

function RfsMapLock.client_onCreate( self )
	self.cl = {
		player = nil,
		active = false,
		camPos = sm.vec3.new( 0, 0, self.mapHeight ),
		move = sm.vec3.new( 0, 0, 0 ),
		zoom = 200,
		speed = 1,
		height = self.mapHeight
	}
	print( "[RFS] /map lock part client_onCreate" )
end

function RfsMapLock.client_onDestroy( self )
	if self.cl and self.cl.active then
		self:cl_clearCamera()
	end
end

function RfsMapLock.cl_n_begin( self, params )
	local player = params and params.player
	if not player or player ~= sm.localPlayer.getPlayer() then
		print( "[RFS] /map begin skipped: not local player" )
		return
	end
	self.cl.player = player
	local character = player:getCharacter()
	if not character or not sm.exists( character ) then
		print( "[RFS] /map begin failed: no character" )
		sm.gui.chatMessage( "[RFS] Map open failed: no character on lock begin" )
		self.network:sendToServer( "sv_n_requestClose" )
		return
	end

	-- Lock AFTER part exists on client (handshake already waited for this)
	local okLock, errLock = pcall( function()
		character:setLockingInteractable( self.interactable )
	end )
	if not okLock then
		print( "[RFS] /map setLockingInteractable failed: " .. tostring( errLock ) )
		sm.gui.chatMessage( "[RFS] Map open failed: setLockingInteractable - " .. tostring( errLock ) )
		self.network:sendToServer( "sv_n_requestClose" )
		return
	end

	local height = ( params and params.height ) or self.mapHeight
	local zoom = ( params and params.zoom ) or 200
	local x = params and params.x
	local y = params and params.y
	if not x or not y then
		local pos = character.worldPosition
		x, y = pos.x, pos.y
	end

	self.cl.height = height
	self.cl.zoom = zoom
	self.cl.camPos = sm.vec3.new( x, y, math.max( 12, height - zoom ) )
	self.cl.move = sm.vec3.new( 0, 0, 0 )
	self.cl.speed = 1
	self.cl.active = true

	-- Shared focus for Player.lua per-frame camera backup
	g_rfs_mapFocus = self.cl.camPos
	g_rfs_mapZoom = zoom
	g_rfs_mapHeight = height
	g_rfs_mapLockReady = true

	self:cl_applyCamera()
	sm.gui.chatMessage( "[RFS] Map open - WASD pan, scroll zoom, RMB recenter, E/Esc or /mapclose to close" )
	print( "[RFS] /map camera active (lock ready)" )
end

function RfsMapLock.cl_clearCamera( self )
	local player = sm.localPlayer.getPlayer()
	if player and player.clientPublicData then
		player.clientPublicData.interactableCameraData = nil
	end
	pcall( function()
		sm.camera.setCameraState( sm.camera.state.default )
		sm.render.setCinematic( false )
	end )
	g_rfs_mapLockReady = false
	if self.cl then
		self.cl.active = false
		self.cl.player = nil
	end
end

function RfsMapLock.cl_applyCamera( self )
	local ok, err = pcall( function()
		local z = self.cl.height - self.cl.zoom
		if z < 12 then
			z = 12
		end
		self.cl.camPos = sm.vec3.new( self.cl.camPos.x, self.cl.camPos.y, z )
		local dir = sm.vec3.new( 0, 0, -1 )

		if sm.camera.getCameraState() ~= sm.camera.state.cutsceneTP then
			sm.camera.setCameraState( sm.camera.state.cutsceneTP )
		end
		sm.camera.setDirection( dir )
		sm.camera.setPosition( self.cl.camPos )
		sm.render.setCinematic( true )

		local player = self.cl.player or sm.localPlayer.getPlayer()
		if player and player.clientPublicData then
			player.clientPublicData.interactableCameraData = {
				hideGui = false,
				cameraState = sm.camera.state.cutsceneTP,
				cameraPosition = self.cl.camPos,
				cameraDirection = dir,
				cameraFov = sm.camera.getDefaultFov(),
				lockedControls = false
			}
		end

		-- Shared focus for Player.lua backup driver
		g_rfs_mapFocus = self.cl.camPos
		g_rfs_mapZoom = self.cl.zoom
		g_rfs_mapHeight = self.cl.height
	end )
	if not ok then
		print( "[RFS] /map camera apply failed: " .. tostring( err ) )
	end
end

function RfsMapLock.cl_recenter( self )
	local player = self.cl.player or sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if character and sm.exists( character ) then
		local pos = character.worldPosition
		self.cl.camPos = sm.vec3.new( pos.x, pos.y, self.cl.camPos.z )
		self:cl_applyCamera()
	end
end

function RfsMapLock.cl_requestClose( self )
	local character = sm.localPlayer.getPlayer():getCharacter()
	if character and sm.exists( character ) then
		local lock = character:getLockingInteractable()
		if lock == self.interactable then
			character:setLockingInteractable( nil )
		end
	end
	self:cl_clearCamera()
	self.network:sendToServer( "sv_n_requestClose" )
end

function RfsMapLock.client_canInteract( self )
	return false
end

function RfsMapLock.client_onAction( self, action, state )
	if not self.cl or not self.cl.active then
		return false
	end
	if self.cl.player ~= sm.localPlayer.getPlayer() then
		return false
	end

	local A = sm.interactable.actions
	if state == true then
		if action == A.forward then
			self.cl.move = sm.vec3.new( self.cl.move.x, 1, 0 )
		elseif action == A.backward then
			self.cl.move = sm.vec3.new( self.cl.move.x, -1, 0 )
		elseif action == A.left then
			self.cl.move = sm.vec3.new( -1, self.cl.move.y, 0 )
		elseif action == A.right then
			self.cl.move = sm.vec3.new( 1, self.cl.move.y, 0 )
		elseif action == A.sprint then
			self.cl.speed = 3.5
		elseif action == A.zoomIn then
			self.cl.zoom = math.min( self.cl.height - 12, self.cl.zoom + self.zoomSpeed * self.cl.speed )
		elseif action == A.zoomOut then
			self.cl.zoom = math.max( 0, self.cl.zoom - self.zoomSpeed * self.cl.speed )
		elseif action == A.create then
			self:cl_recenter()
		elseif action == A.use or action == A.exit or action == A.jump then
			self:cl_requestClose()
		else
			return false
		end
	else
		if action == A.forward or action == A.backward then
			self.cl.move = sm.vec3.new( self.cl.move.x, 0, 0 )
		elseif action == A.left or action == A.right then
			self.cl.move = sm.vec3.new( 0, self.cl.move.y, 0 )
		elseif action == A.sprint then
			self.cl.speed = 1
		else
			return false
		end
	end
	return true
end

function RfsMapLock.client_onUpdate( self, dt )
	if not self.cl or not self.cl.active then
		return
	end
	if self.cl.player ~= sm.localPlayer.getPlayer() then
		return
	end
	local move = self.cl.move
	if move.x ~= 0 or move.y ~= 0 then
		local step = self.moveSpeed * self.cl.speed * dt * ( 1 + ( self.cl.zoom / 200 ) )
		self.cl.camPos = self.cl.camPos + sm.vec3.new( move.x * step, move.y * step, 0 )
	end
	-- Must set every client frame - one-shot set is ignored by SM camera
	self:cl_applyCamera()
end
