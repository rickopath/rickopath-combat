--!strict

-- just a facade over Packages.Signal (fastsignal). one swap point if we ever ditch it - nobody
-- needs to hand-roll a second GC-friendly signal impl, that's a solved problem, move on
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Signal"))
