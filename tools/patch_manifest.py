"""Adds HUDDLE's permissions + app name to the generated Android manifest."""
import re
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p).read()
perms = '''<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    '''
if 'android.permission.CAMERA' not in s:
    s = s.replace('<application', perms + '<application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="HUDDLE"', s, count=1)
open(p, 'w').write(s)
print('manifest patched')
