import 'dart:convert';
import 'dart:typed_data';
import 'platform_logos.dart';

// Square service icons from the existing website artwork, not rail wordmarks.
// Other services already have square bundled artwork in platform_logos.dart.
final _decoded=<String,Uint8List>{};
Uint8List? bundledPlatformBadgeIcon(String key){
  final data=_icons[key];
  if(data!=null)return _decoded.putIfAbsent(key,()=>base64Decode(data));
  return const {'max','apple','paramount','peacock','iwant','iqiyi'}.contains(key)
    ?bundledPlatformLogo(key):null;
}
const _icons=<String,String>{
  'netflix':
    'UklGRsABAABXRUJQVlA4ILQBAAAwDgCdASpgAGAAPpE8mUelo6KhMBR7GLASCWIA1IA4K5vFhv+yIJjuAPIA65n0L+mCyG1LlUer'
    'phxsKt3Mmgo/mSU0DTnXhx/70DkWbXTlX+BWjPYFMIeqb/Zm1PIZ3bqNbT8r2D16Dy/TBttFCBOD3SwMAWECMRBKwAD+/F0H6Zko'
    '6Npqt2+tVEILCL0XDKzpJiIWV4uLR/cyhTgW/67DYyyCLaC0hqJrsDof0OPZ9/96qbAI5mGUGOcG+Sqt9ZKaxcR5P5McciUcyngV'
    '5iNj+eZfQRTU9i/uVl4gOcAqqzA6sVkrYl4hCCkyvi4wWGPgvymRDY9C/KBik02S6k6SrcRQ5KgVZAli9KLgmKB30PrlnDiPtwKD'
    'Ol2GZzH145VNU6vYb7yS5YjIgsbq0yin3au71cXQgDVTEGiDerkhLKpen9GqrwlkfRuNxy9WmNJorIUizJeER1C9X5+GTYMGunUK'
    'TN5l0ET1ZgD+3Fih7ramHzenaQ0qhvzYj6238b1pmFc97f47wfleTxnvXgJ0bEFZDnlNoT0RUBH0eMBHqRzQ0zop+nFyjWsg2pRW'
    'a9UwAAAA',
  'disney':
    'UklGRiIFAABXRUJQVlA4IBYFAACwFwCdASpgAGAAPpE+mkoloyikpHzMoRASCWMAxcBtPZ0WvDCEXjIbhfnl9NP3m2vQ6wP4T8jM'
    'oX+t4QdqnIU/pPEBpAtADw+s5r1F7BX8v/uP/K9ar2M+jgdmGA5o8/NXhRo8I5HBR2CTyL8yRTQCOAVw9rYgJ6amJ7AGutlgy4uw'
    '+uIUzuCL2Za+r82AEkFimuinpTrI59zh4XhBAPfEbtCbgE4gksF2gXjL99F5Bc49SWCi+gXyNuTqp6O4h4IM/9WqVEQA/vmsdt6u'
    '6QgTbL+Hb7bsHzOEpKU7nw6EiBEjRLY054bonpbKqDlf0N1vwvqQ1H8e/rkn08xZGi9tW0yPP1im99+lsXKqO4Lf7eE/fJBy9rvj'
    'dGby8giv/Nd3fNT2pP+QOr+fC7/MIaJOqIIWWdsE4WVzWheh4YswOatPnMrK7N+AmzMwVvfLLoyoCKUYSFTzvoIpfi99pwrV42W4'
    '/qTQKpWwW+loeBoieV6ohe4m0prAKTbK5YqTtp4q9gjMw7akpXHnGgHgxhqDUwg40MQJohk2ZSwnlyvD0U/IL9avf0/uURVigtXZ'
    'Lcv/fuuaPsRhNxzMGdqxhbnX6oOYmAJxeSZv5BViHxuA1iSi1wPDp1rsfKOMC6O+rUcEZRt+DpW1yn4hPlA8oLOnzndklNludpKs'
    'c+VU/WLqmw0IN1nmABUI9vYcj5+PUCFuB9AU1j4DZdElgpYYO/GvxKjWTRSk6vnhmD96RYrkSXEr5na8Gizoct7Llyp9IMT9WxN6'
    'j3gKckvZq5vf/8yk8DzHkjRsEnJJRKKc9T3dv9uzgN+P8B3B4HpIShqQuUKB+x3GG/AJLrwDqmEtQmvtTqay2CMNSKB0SH2j7CMN'
    'xG0CgB8i7rY0libIxfcxM5H4sUNnmXso57F4RjyoWlw9SpTy3lVpSCQjEv5itrjNL1gPwY4MC8Fi2J5r2L6EVCrwEbvXgABBdABe'
    'Nu53v84kS1RukYdDe2G7APheCbg9AhSykgoS2fwk+uGL4NojC1Z2XKRlzPhnplhepPrLu9sC62PZe73ygf+yVXhg2PxUvzb2EnPk'
    '0QrLMl+8ULqplj5ZdqVF7ev8ea+HrmTD5p9Zl+ynvAbuTERBGHGof4XzJ2nEafB3tNcpwI8/+/9hUlQ0uAzuyJDG7t6v1c8zPPZk'
    'IFjJmxNNCC/zh3kvEAKGL1O2Tv+OZSlmgqNaXI/W7hZe7/gb7OQiGkwZ3rz4jfj9WnCGq9KhME5uUVz5B8uzNVTeChWm4DNxzFUS'
    'Op/l1y8WG66WCESNZ9c4bknpdVzriAPNy1Z3W2otBB5B2HaH4qv2Iz8n8O2QoWjkMs4rRXiaE1h1HLrCEiKk1pYwnx5Q5rrsNXpd'
    'qN68LNf74mEdA5PcGvR/wFz+BimGWNRw7y2qa7ipwQlsu5qH1DagWU/mCcy6tLditps1qFvk/r+QES+pD0YGEVuSUkRW/v01q7qP'
    'DuzVpm6LDIM8w7ssG5XGlD8isYjmQ2BjP/hSujvcSWHxBih0S34sXKEZ+ycoooD/Z/uB0fwxHPiML3gTrUbG2RQvtZkHnopSC9vG'
    'b8P8ivy3ZW2d7tOF/SmnCkS3my16GKVqi5LnR8f7PVk4nGLIG8ZkIz8I3v/gxCSkGEy1TqQzcNhaAfPH0IdyHt7Z/wAuNc1luR0a'
    'Y1rVW76SeJNP8uj/3van/63qvJ49rzbQOw+MWVIKU+fL48RbhebRbmumLzMAAAA=',
  'prime':
    'UklGRvAGAABXRUJQVlA4IOQGAADQHwCdASpgAGAAPpE6lkelo6IhLVqs8LASCWwA0I3h3n5P/hf5L6NtafxXBXEpr0eoX80+wBzj'
    'P2O9QH7C/s97N37H+4X9l/YA/w/9y6wr0I/Lc9lj+0f+H0z9WP8O9ff+Y8I/In7WkQXFfVv9v/UvNrvn+KWTzdCMud7hqid8NcJo'
    'AeK1oRl6c1NTs1oCU7k/qAk7ys8TgNinVQGRUj5MlZmw22ua/GkDPQzhj1UFFONBOoQ9xoQ3+wlbg2KP3IWI6kLhHO58NbXcW3FY'
    '/vVDO58B54bCeNF8pPQTAkRHUmwYJcKhsYZpAibMErat3SMzQ+XO1J/mT2KAxI+dUUYJAlaR8QE2gAD+/EoFARCmH5vwH+BC0ADD'
    'O+BPSHoW3K0/VZuUZPOGICtcRtqz6B/UKHqSqhZMjmOYEviFnJfCtbTiM+CsEhEXWY8X3gfXDzkfnZlXMT9iJNXub6S66P97qnzs'
    'AVmwvVUwKQRPePi5j1aKnoyZx6V+ekLIblQjhP8Rx9TJfidI4APnz1vxu5cB1mPNJ7T7p8EoZ/qPSv8r8BFcw4r5f1+fWg6YCBa0'
    'g7qTq/evJmb0w5ccdoJFKc/HOGnZjCx9B6m87Ey50TOAes8+fcprOqQ2plyj/G3hvO1DDlGP+nCVJwdlTXbVFm8WGHJDDZ7Tug+Y'
    'o8xtzKpRcRxekQYefTvrRU7qmS4icJwM2lIQOKKfXcDkR4gSSJNoKySd28j2GqbK6i9yXTk5KhYYOyJiCQawvuyGE28HcyVUCrAo'
    'FRKufNvdFQvGL+ONhFkNgtomNB0oTXjr0eOi3VE60yS6eZo+fRFcHmk8HGIGhbJNBJ0HMw5H5Wc+eW6bKDRY+4KJgcUxe13DnYgb'
    'ptOc7VEfLfcJQMha8w04gsw+rPGCCs3+ekrJrxNK2AO6Tej5iWS1JXlWbQFvC2X7NwNCFBpTSf+CkjGkjmXtX/Y7k52UnQRJDCRv'
    'ZBC6587Yz/hus2wSkWl5k198zNNLEJ2ZFABnhcsl0E8IC5LVVGpX6SJTRYDVYHVoqwSS2+YOrkjLGHdLteMD1XtIQ2S8xxt1CvBz'
    'ofB5nCoU9o1L6RS3lmcXxC0FoCA7JxaqTEfN3FrirD9JjWt3ItNPqoJOzHrxm0mRbpLADvXWAQ3MqVzKjTrYeh99dyNYGS+NxOxa'
    'xyuGBl2+moFOja02YJkbY5uQCKEPV2RSecTr6x/csxbGDarpQglhLCZ20gA7WwtEoNqq3h2zrh5FZI+itRMFAC6/r3eeURhOyG3u'
    'lp/o8rqCiz91XtF5EFNyMbU0Hu2uqBt+4v8Dn22mg6OQ2igQhNjgzxdhgreffCNczhf0kOEVbuQapzIes6pY6YJdpDfs0G//ztxO'
    'fINEikyVf7/ZEomf+AsPh3GXCEUn237VoYRYI6Wnt/bKJpEvNdjPIcN12djzb6Ot7YeWoQs2BFvOR94J9zthJUsCqW+upjiyomLp'
    'V+XtYFXkvB/KoxC8rOGoSs9vrBrtt+sZigC97i4PY0V1VpZ0SamOvF/NQTTee2+vr6pzJHg6J+JPfz7fTzlJnepjuCJonFj/KcqP'
    'FfjSvyW7lS8Qv3GR0vQWEdfR04GfL7O++itjcyxAMAy8cGw/aZrxwuVl+fOptGgBNlauNWZwM9hxFHdfZw7VJJ1t807gCv4kQP+C'
    'Yk9btdMiRyaS+/lQPOc7+4Tw4+M37z8cXOclIA58PHJ5K+CLv6yVrCcXylDPfOvQLbdcv8H/+szMUIaUiAqgQpnQFwuceZTRZMUR'
    'PfiKPp60D4PhvfDXheQxH+vPR4lJlbojk/j+ltVa8fxNkOaekUYtjh8569cwbLVZzYT9t0lFcBGaU50Gym5S0YMdKrnwIZgDydMV'
    '2qveTkpBh9386oeBgsZK2Qg0htPV0msZ4Me1hyk26iB69LYXzLntUMM/5TMa82ZtA5OmWoCjqLkgKj/ggMvG5yF7Y69d+McWwuNR'
    'tFeq0IVj+rTQvQu8U4lPNb7u/Kr8HrbP41aFpjOmm2rvJxvEMGCIr8jDL/yNM/qSHMHDpXuYnnjq82aTMwB/6FDwtSF1uSJUcYES'
    'yKHfCAesMHznJtCwG2oXQH4r64pndICHqdx0KyX1nI/fNy78xSlPOiq9wVPWZcqF5vZCJXmSQ7xxCG/4GX0dxqUU0E326l9vrweT'
    'sGfi54PWIei7NyRJVaOyWossW1aWQI07737hVhpnAyn1kov785zE1TUyl3m9NKbFeanJedGe1QWo34vktcnidAF5GvGtFnyscPhV'
    'etXlsy/sJJmyNxZS6wrq6Th/C52sX8wgcnla65K1BCkWuJJSoKp4C3JlKP4oH4Im9hoAIyweIAAAAAA=',
  'crunchyroll':
    'UklGRooDAABXRUJQVlA4IH4DAAAwFQCdASpgAGAAPpFEnkmlpCMhKBOaELASCWgA1ee4+P/kZ+TPyd1n+wbtJMHmp81eNr1FeYB+'
    'nfSA8wH7b/sB7w3oe/yPqAf2DqE/QA8tP2Xv2d/br2gM08fSuxhInyIFT/e+GYbPTA94zT4v29Ps/hk0nDGLrHWK02FbXI82Malz'
    'mfVUmEdMfwzd7AhgMDphPwxkhJfNb05l/gldqO/T9SdAeGy9ZoMhLPMVx9QSWp6AAJv//bjUHkbPlw//96q9lOsH18ABY5PfXAVv'
    'RsJBLnaNrdYvhN1c/etUS3+Z2w+KkOP06tNOonarictCEJCpArThJtotk0uFEQetpmxkdO8hmUEqPaV7G+lwezRHxTwbGSTpL1Bw'
    'XWcM+7PbIjB8ArzvXl1Db7TttLkqW5n/s7RIpNbLvrCSi+3+3qr5xRJBC7oYoePIgVqxvPTIxuKUujbh9m/xT+iMqGydW/dUE2fQ'
    '3vWNlW/GQaIgVuHhnKlvspRTdv68M2fnxzp7K7wBE10Wsag1UPdgx665xRmKri+qX2S9Zz6pQIuahio1vJI9FwLKNC387979Jc8Z'
    'ceL+W0JLECbrhfF53sGWm1OQafx/65ubWciSjvz3qXwKZNcnUcnXXkWcu2ouhDvN4USAvk/F9qxvXC3mmoqEe+iTM+/yCG5ulGqR'
    'lvPSlGceAgg3V7rV1RDCwaUQBRxXK69gGIJURV3l39DFwS0P3fShh1jId8hXfc/lgm4C1at7vd0v7gXbSyuBM2C6OYekJvYRu9fB'
    'XAUGkSVeMXKZYpO51k4WeBvZDYnK+c5ygmVUOJiUUZHU2WJ/+HdIsyZ3dnidE595K8UqMcVG4MInTao9yVzqHDEFdi9joDaTBXv/'
    'KJpp1qx3mGeVICO8y3Wh00joVze3jPgzZ0PJ0Q2yc18z+Y+YSkxyk4rY1A0/ImoLm32wnpqq/TQS5vLrcAgaxbm9SIcfqZX+qj2u'
    'gMgKZRnAv9tJ2833/GN0pXjMLyX2+IDjLFmw+fK+47doi6SKhatKRxtGbMd4Gh1OyltjW0LSuR/B5wnJ2U34UbdxBU0XqrJoC7J3'
    'HVKj4FZRYlVI5shoZ1V33Tb4KysHDs5ETdadAPEwOb6qjhWkSYR+Dl12Wvgvhe//3BJ8+JRwdJ0ESfByvKOuPaYEmO1AG3mDbHJP'
    'l7KMcWdF5En4AAAAAAA=',
  'hulu':
    'UklGRqwCAABXRUJQVlA4IKACAACwDgCdASpgAGAAPpFGmUmlpCKkKraoWLASCUAZGYyKaewHQA3mn0AOlgRuO2RXMdy2JEV0rIK/'
    'pEKJnwx8chjkieSov3qA8XaTYXvkzBAbZ+y8Yfs3w27eq5KJxk4l3fYkcqsvHU6jiDRzJ+7RCQhUkmjUeT25DyOut/WurQAA9wRf'
    'h3qv/1lf/5OP/5lf7V2OYdMfJyEFGSzRQK73r6qZVhsxnVS3NpaMp30RBQOKCLKmo87P5bQp0ol1ROZOPlGLcHiHRXxORLjhTd4f'
    'aH7HatgpaYcxPOXI2hSdf9q8us6vgv8fs22Ei+Ob+FTNboHv6N+4EoMa2E/wUFXNkP6EWfycggAxT5EtqryNWru3j2aMMZbjC+CA'
    'v2z7GMO7NZ4VmPVrgPOYzjhDTl8BvB43WscqnB7ZizgIBz/lOYl6CYogLSLGbHSXpUTvPonsDnGzB5CS65zWQMM7W4q7yowC9xLg'
    'PDD76T3zej7nnWmt1qFssLJceZXhRz7X3ouD2CuEPG8GTJWufqXD3+TP8NqANYU8Zmoobzv8gU349WunoEAmNjKomjOPQQ5CE9ag'
    '/oOEM39+yS+cK7AaeNEOONvnbvDKaWd48tW/RmN3/c69l7oiYpsPwdaNMdU268Bi5bGFc6KhqgpJt1lG++ejTC+4me+1Z1MD5IVG'
    'n3Rz50uAw5PfoKoaAqwsRlctTNn9/IRFoVcSGEh2XOn1DB0ZKgwRs+bLYm+Ei2VspqUOISoJQNlrZE1YiVk61ftPcVfS5ebQeizV'
    'tv6J0AfvbgoXbfU1rDpSGsMK7o1xzqbFRBR/krvQJFFy+oFdRrTUqcr5WBjrj27+LwDVwgrMvXITjYTP1+k6w297tuYs+IrvvFad'
    '2w9sKWfWXIoUMhD+QfmUFAA=',
  'viu':
    'UklGRiAEAABXRUJQVlA4IBQEAACQGACdASpgAGAAPpE+m0glo6KhLxWqiLASCWwA0X4BPN/zf5GeyVWf8NumVAeaxyp43fVB5gn6'
    'r9IDzC/tR6vf9u/Un3l+gd/Sf9J1mvoZ+Wr+3vww/t5+5Xs7RX50f2gyu4eIkLmpTbSRJwq7iHu98bcaTHj8Tfrnj58GKwNt2AQh'
    'EelWNclutVAdiWfMZmY+zMbC/e7SBSL9HzZyknwAIoLZD8z33J4YZ2gKbwwZyWWNlVgVOjF6PZh04oWTPVdRQAjwG2hkY3kdwWbA'
    'AP7xcg/90d/tHf7R38S3/xoSUxXW1fbe+JcvCW9mGkFxyuyfUQp14mCfQP9nkTMwjkAl1sKF9A3pL3C9nzTlBrRyEKWOxvke99vz'
    '5CS7JPk9ChuBcWo1wrQ/roTPUVMwLnGEA4B7maBytyDQVFJ1EZwQVoF/9qQgy/OqKQTMaeZ5rv3sICN0SM9pOpZLHn5LPDIEDxcz'
    'JU7708sEE9sRYi6kBF7t7R/pEFa6DepcmDkx36oa5+TWAO7085tqj7dEYHGKj6ejPmAgjvQ1L6ikZAbWvMI8rt2Q7jPBFt+2tYf+'
    'dfy9kbDPe9vVR11dCZaa2JGNcb0Ll9IPr3yH3ixXZv4YPdTQdxPYSwrsRTzQLFw/Kfn5kTI2sj4K9Cxs3owYPFIMhiJVy/klrO3w'
    'dKh9U8fHn725dXOAHyFv1Ha90odNaRhQUx3/BTd+wFt5eI+tXwZyiuImF4Ydq1JJT2oGFjP2625VuYYCkR3yvdjwREoKdCaZ/7Kp'
    'c6Fq2VJk0RroE/tcHOsWXIB1QJx+qsQtBNHFlCFEj4LxO1RftSbtHMKnPMwNgiMABgSou/SqNPHxRCo2fcseJYw+FJMV3TxU5KWh'
    'sLI/tGCtn+3mRNXELJP191M90K8jj/4wDOBGGU158zG9W+pC7noI2ilSH5hRcTrwF6iP0+XM4C+SB7fiqkW/bgViHcxUynmoVsoY'
    'Hi4GKDAi5uv6C7Q9q1HXM5htG2IxJNGhzGhOKLaPL8X43CZO8E3BnrqspIOFCko9ATAyEAZtsHqgsA7TB8WkFem1ybM7jVNy+nau'
    'HVSX2ju0bdhwg0jutl/7oiWxvDZq+OkxDP0Tgy4UxebqalAyfUyrkXFPKogHjxk7/xdS3JliLEUdV/r06rmybh9iEXipQm+IEUwl'
    'zj6xitWmFNzMp2MPCqAbiSEZgUFMrQL1HIuf8IgLCY4hfEDynfZBy9AyHfbwLqTtFnuS4/V7aZUF6UCVWNvvGTc9+h8UokIO5CwN'
    '3S8vaIKLUaaU/NzL0jHoug3vIkcK/CHhVrjXfZMTZxLyCWGUNU5r2EgnhnqxH/nE96Fs6uqMcwkVOnELeIzuU2oZ+niAm8JBg0ZV'
    '+4ag+bhSpIzxJxYWAAA=',
};
