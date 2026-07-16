-- Config.Access_Profile
-- The subscription profiles and their monthly price -- the BILLING BASIS. A subscribed user is
-- assigned one profile; their monthly charge = that profile's price. The profile also presets the
-- Security.Application_Users module flags (preset lives in the app: _PROFILES).
-- IDEMPOTENT CREATE so pricing survives redeploys; the .Data.sql reseeds it (vendor-managed).
IF OBJECT_ID('Config.Access_Profile') IS NULL
CREATE TABLE [Config].[Access_Profile] (
    [Profile_Key]   [varchar](50)  NOT NULL,   -- 'full' | 'clinician' | 'front_office' | 'no_access'
    [Display_Name]  [varchar](100) NOT NULL,
    [Monthly_Price] [decimal](9,2) NOT NULL,   -- vendor system default (GBP/month)
    [Display_Order] [int]          NULL
);
GO
