include("shared.lua")


--------------------------------------------------------------------------------
-- Random number generation
--------------------------------------------------------------------------------
local random = math.random
local sqrt = math.sqrt
local ln = math.log
local cos = math.cos
local sin = math.sin
local pi2 = 2*math.pi

-- Generate at least 60 random bits
local function rand60()
	return random() + random()/(2^15) + random()/(2^30) + random()/(2^45)
end

-- Generate random gaussian-distributed value
local function gauss_random(x0,sigma)
	local u,v = rand60(),rand60()
	if u == 0.0 then return gauss_random(x0,sigma) end -- Remove singularity
	local r = sqrt(-2 * ln(u))
	local x,y = r * cos(pi2*v)
	return x*(sigma or 0.5) + (x0 or 0)
end


--------------------------------------------------------------------------------
--
--------------------------------------------------------------------------------
local passengerModels = { -- Common passenger models
	"models/metrostroi/passengers/f1.mdl",
	"models/metrostroi/passengers/f2.mdl",
	"models/metrostroi/passengers/f3.mdl",
	"models/metrostroi/passengers/f4.mdl",
	"models/metrostroi/passengers/m1.mdl",
	"models/metrostroi/passengers/m2.mdl",
	"models/metrostroi/passengers/m4.mdl",
	"models/metrostroi/passengers/m5.mdl",
}
local rareModels = { -- Less common special models
	"models/metrostroi/passengers/m3.mdl",
	"models/metrostroi/passengers/f5.mdl",
}


function ENT:Initialize()
	self.PassengerSounds = CreateSound(self,Sound( "subway_stations_test1/peoples.wav" ))	
	self.NonPassengerSounds = CreateSound(self,Sound( "ambient/levels/canals/tunnel_wind_loop1.wav" ))	
	self.ClientModels = {}
	self.CleanupModels = {}
end

function ENT:OnRemove()
	self.PassengerSounds:Stop()
	self.NonPassengerSounds:Stop()
end
--------------------------------------------------------------------------------
-- Is position in the world free or blocked by world
--------------------------------------------------------------------------------
local trace = {}
local function isPositionFree(pos)
	local ped_size = 16
	local ped_legs = 8
	local ped_height = 90
	
	trace.start = pos+Vector(0,0,ped_legs)
	trace.endpos = pos+Vector(0,0,ped_height)
	trace.mask = -1
	local result = util.TraceLine(trace)
	if result.Hit then return false end
	
	trace.start = pos+Vector(-ped_size,0,ped_legs)
	trace.endpos = pos+Vector(-ped_size,0,ped_height)
	trace.mask = -1
	local result = util.TraceLine(trace)
	if result.Hit then return false end
	
	trace.start = pos+Vector(ped_size,0,ped_legs)
	trace.endpos = pos+Vector(ped_size,0,ped_height)
	trace.mask = -1
	local result = util.TraceLine(trace)
	if result.Hit then return false end
	
	trace.start = pos+Vector(0,-ped_size,ped_legs)
	trace.endpos = pos+Vector(0,-ped_size,ped_height)
	trace.mask = -1
	local result = util.TraceLine(trace)
	if result.Hit then return false end
	
	trace.start = pos+Vector(0,ped_size,ped_legs)
	trace.endpos = pos+Vector(0,ped_size,ped_height)
	trace.mask = -1
	local result = util.TraceLine(trace)
	if result.Hit then return false end
	
	return true
end


--------------------------------------------------------------------------------
-- Populate platform with pedestrians
--------------------------------------------------------------------------------
function ENT:PopulatePlatform(platformStart,platformEnd,stationCenter)
	-- Define platform
	local platformDir   = platformEnd-platformStart
	local platformN		= (platformDir:Angle()+Angle(0,90,0)):Forward()
	local platformD		= platformDir:GetNormalized()
	local platformWidth = ((platformStart-stationCenter) - ((platformStart-stationCenter):Dot(platformD))*platformD):Length()
	
	-- Create pool
	self.Pool = self.Pool or {}
	
	-- Fill pool
	math.randomseed(self:Seed() + #self.Pool)
	local N = math.min(self:PoolSize() - #self.Pool,32)
	for i=1,N do
		local pedestrian = {}
		local iterations = 1
		while iterations <= 16 do
			-- Generate random constants
			local a = -1
			while (a < 0) or (a > 1) do a = gauss_random(self:GetNW2Float("X0"),self:GetNW2Float("Sigma")) end
			local b = math.abs(gauss_random(0.00,0.20))
		
			-- Create random position
			pedestrian.distance = b*platformWidth
			pedestrian.pos = platformStart + platformDir*a + platformN*pedestrian.distance
			
			-- Check if pedestrian is not standing in a building
			if isPositionFree(pedestrian.pos) then break end
			iterations = iterations + 1
		end
		
		-- Random other parameters
		pedestrian.ang = platformN:Angle() + Angle(0,math.random(-50,50),0)
		pedestrian.skin = math.random()
		pedestrian.scale = 0.98 + gauss_random(0,0.03)
		pedestrian.model = table.Random(passengerModels)
		
		-- Add to pool
		table.insert(self.Pool,pedestrian)
	end
end


--------------------------------------------------------------------------------
-- Think loop that manages clientside models
--------------------------------------------------------------------------------
function ENT:Think()
	--self.TestSound = CreateSound(self,Sound( "subway_stations_test1/orange_1.mp3" ))	
	--self.TestSound:SetDSP(117)
	--self.TestSound:SetSoundLevel(105)
	--self.TestSound:SetDSP(58)
	--self.TestSound:Stop()
	--self.TestSound:Play()
	--self.TestSound:ChangeVolume(0.7)
	if self:GetNW2Bool("MustPlayAnnounces") then
		self.PassengerSounds:SetSoundLevel(105)
		self.PassengerSounds:Play()
		self.PassengerSounds:SetSoundLevel(105)
		self.PassengerSounds:ChangeVolume(0.3)
	else
		if self.PassengerSounds:IsPlaying() then
			self.PassengerSounds:Stop()
		end
	end
	if self:GetNW2Bool("MustPlaySpooky") then
		self.NonPassengerSounds:SetSoundLevel(105)
		self.NonPassengerSounds:Play()
		self.NonPassengerSounds:SetSoundLevel(105)
		self.NonPassengerSounds:ChangeVolume(1)
	else
		if self.NonPassengerSounds:IsPlaying() then
			self.NonPassengerSounds:Stop()
		end
	end
	self.PrevTime = self.PrevTime or CurTime()
	self.DeltaTime = (CurTime() - self.PrevTime)
	self.PrevTime = CurTime()
	
	-- Platform parameters
	local platformStart = self:GetNW2Vector("PlatformStart")
	local platformEnd = self:GetNW2Vector("PlatformEnd")
	local stationCenter = self:GetNW2Vector("StationCenter")
	
	-- Platforms with tracks in middle
	local dot = (stationCenter - platformStart):Cross(platformEnd - platformStart)
	if dot.z > 0.0 then
		local a,b = platformStart,platformEnd
		platformStart,platformEnd = b,a
	end
	
	-- If platform is defined and pool is not
	--print(entStart,entEnd,self.Pool)
	local dataReady = (self:GetNW2Float("X0",-1) >= 0) and (self:GetNW2Float("Sigma",-1) > 0)
	local poolReady = (self.Pool) and (#self.Pool == self:PoolSize())
	if (not poolReady) and (stationCenter:Length() > 0.0) then
		self:PopulatePlatform(platformStart,platformEnd,stationCenter)
	end
	
	-- Check if set of models changed
	if (CurTime() - (self.ModelCheckTimer or 0) > 1.0) and poolReady then
		self.ModelCheckTimer = CurTime()
		
		local WindowStart = self:GetNW2Int("WindowStart")
		local WindowEnd = self:GetNW2Int("WindowEnd")
		for i=1,self:PoolSize() do
			local in_bounds = false
			if WindowStart <= WindowEnd then in_bounds = (i >= WindowStart) and (i < WindowEnd) end
			if WindowStart >  WindowEnd then in_bounds = (i >= WindowStart) or (i <= WindowEnd) end
			if in_bounds then
				-- Model in window
				if not self.ClientModels[i] then
					self.ClientModels[i] = ClientsideModel(self.Pool[i].model,RENDERGROUP_OPAQUE)
					self.ClientModels[i]:SetPos(self.Pool[i].pos)
					self.ClientModels[i]:SetAngles(self.Pool[i].ang)
					self.ClientModels[i]:SetSkin(math.floor(self.ClientModels[i]:SkinCount()*self.Pool[i].skin))
					self.ClientModels[i]:SetModelScale(self.Pool[i].scale,0)
				end
			else
				-- Model found that is not in window
				if self.ClientModels[i] then
					-- Get nearest door
					local count = self:GetNW2Int("TrainDoorCount",0)
					local distance = 1e9
					local target = Vector(0,0,0)
					for j=1,count do
						local vec = self:GetNW2Vector("TrainDoor"..j,Vector(0,0,0))
						local d = vec:Distance(self.ClientModels[i]:GetPos())
						if d < distance then
							target = vec
							distance = d
						end
					end
					-- Add to list of cleanups
					table.insert(self.CleanupModels,{
						ent = self.ClientModels[i],
						target = target,
					})
					self.ClientModels[i] = nil
				end
			end
		end
	end
	
	-- Add models for cleanup of people who left trains
	self.PassengersLeft = self.PassengersLeft or self:GetNW2Int("PassengersLeft")
	while poolReady and (self.PassengersLeft < self:GetNW2Int("PassengersLeft")) do
		-- Get random door
		local count = self:GetNW2Int("TrainDoorCount",0)
		local i = math.max(1,math.min(count,1+math.floor((count-1)*math.random() + 0.5)))
		local pos = self:GetNW2Vector("TrainDoor"..i,Vector(0,0,0))
		pos.z = self:GetPos().z
		
		-- Create clientside model
		local i = math.max(1,math.min(self:PoolSize(),1+math.floor(math.random()*self:PoolSize() + 0.5)))
		local ent = ClientsideModel(self.Pool[i].model,RENDERGROUP_OPAQUE)
		ent:SetPos(pos)
		ent:SetSkin(math.floor(ent:SkinCount()*self.Pool[i].skin))
		ent:SetModelScale(self.Pool[i].scale,0)
		
		-- Generate target pos
		local platformDir   = platformEnd-platformStart
		local platformN		= (platformDir:Angle()+Angle(0,90,0)):Forward()
		local platformD		= platformDir:GetNormalized()
		local platformWidth = ((platformStart-stationCenter) - ((platformStart-stationCenter):Dot(platformD))*platformD):Length()
		local target = pos + platformN*platformWidth
		pos = pos - platformN * 4.0 * math.random()
		pos = pos + platformD * 16.0 * math.random()
		target = target + platformD * 128.0 * math.random()

		-- Add to list of cleanups
		table.insert(self.CleanupModels,{
			ent = ent,
			target = target,
		})
		
		-- Add passenger
		self.PassengersLeft = self.PassengersLeft + 1
	end
	
	-- Animate models for cleanup
	for k,v in pairs(self.CleanupModels) do
	--	if not v or not IsValid(v) then self.CleanupModels[k] = nil return end
		-- Get pos and target in XY plane
		local pos = v.ent:GetPos()
		local target = v.target
		pos.z = 0
		target.z = 0
		
		-- Find direction in which pedestrians must walk
		local targetDir = (target - pos):GetNormalized()
		
		-- Make it go along the platform if too far
		local distance = pos:Distance(target) 
		if distance > 192 then
			local platformDir = (platformEnd-platformStart):GetNormalized()
			local projection = targetDir:Dot(platformDir)
			if math.abs(projection) > 0.1 then
				targetDir = (platformDir * projection):GetNormalized()
			end
		end		
		
		-- Move pedestrian
		local threshold = 16
		local speed = 1024
		if distance > 1024 then speed = 256 end
		v.ent:SetPos(v.ent:GetPos() + targetDir*math.min(threshold,speed*self.DeltaTime))
		-- Rotate pedestrian
		v.ent:SetAngles(targetDir:Angle() + Angle(0,180,0))
		
		-- Delete if reached the target point
		if distance < 2*threshold or LocalPlayer():GetPos().z - v.ent:GetPos().z > 500 then
			v.ent:Remove()
			self.CleanupModels[k] = nil
		end
		
		
		-- Check if door can be reached at all (it still exists)
		local count = self:GetNW2Int("TrainDoorCount",0)
		local distance = 1e9
		local new_target = target
		for j=1,count do
			local vec = self:GetNW2Vector("TrainDoor"..j,Vector(0,0,0))
			local d = vec:Distance(v.target)
			if d < distance then
				new_target = vec
				distance = d 
			end
		end

		--if distance > 32 
		--then v.target = self:GetPos()
		--else v.target = new_target
		--end
	end
end


--------------------------------------------------------------------------------
-- Make sure entity is not drawn
--------------------------------------------------------------------------------
function ENT:Draw() end