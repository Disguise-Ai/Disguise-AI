-- Create profiles table for storing user data
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    name TEXT,
    personality TEXT[],
    text_samples TEXT,
    response_style TEXT,
    message_length TEXT,
    emoji_usage TEXT,
    flirtiness TEXT,
    is_premium BOOLEAN DEFAULT FALSE,
    trial_start_date TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Allow users to read/write their own profile
CREATE POLICY "Users can view own profile" ON profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles
    FOR UPDATE USING (auth.uid() = id);

-- Allow anonymous access for the app (using anon key)
CREATE POLICY "Allow anon insert" ON profiles
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow anon select" ON profiles
    FOR SELECT USING (true);

CREATE POLICY "Allow anon update" ON profiles
    FOR UPDATE USING (true);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS profiles_id_idx ON profiles(id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to auto-update updated_at
DROP TRIGGER IF EXISTS update_profiles_updated_at ON profiles;
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
