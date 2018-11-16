describe("eink optimization setting", function()
    setup(function()
        require("commonrequire")
    end)

    it("should be correctly loaded", function()
        G_reader_settings:saveSetting("low_pan_rate", true)
        assert.Equals(require("device").screen.low_pan_rate, true)
    end)
end)
