--!strict

-- run this project standalone: `rojo build test.project.json -o test.rbxlx`, open it in Studio,
-- hit Play. results print to the Output window. this file, TestEZ, and everything under this
-- folder ONLY exist under test.project.json - default.project.json (the real game) never
-- references any of it, so none of this ever ships and TestEZ is never a runtime dependency of
-- your actual game. see wally.toml's [dev-dependencies] comment for the same point made there.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestEZ = require(ReplicatedStorage.DevPackages.TestEZ)

local results = TestEZ.TestBootstrap:run({ ServerScriptService.Tests }, TestEZ.Reporters.TextReporter)

if results.failureCount > 0 then
	error(string.format("Combat framework tests: %d failure(s), %d passed", results.failureCount, results.successCount))
else
	print(string.format("Combat framework tests: all %d passed", results.successCount))
end
