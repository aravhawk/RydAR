import pandas as pd,glob,os
def rd(y,name,**kw):
    p=[f for f in glob.glob(f'/tmp/curveaudit_fars/raw/{y}/**/*',recursive=True) if os.path.basename(f).lower()==name]
    return pd.read_csv(p[0],encoding='latin1',low_memory=False,**kw)
