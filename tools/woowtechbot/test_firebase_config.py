import copy
import unittest
from firebase_config import convert

class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.doc={'project_info':{'project_number':'123','project_id':'assistant-test'},'client':[{'client_info':{'mobilesdk_app_id':'1:123:android:abc','android_client_info':{'package_name':'io.woowtech.agent'}},'api_key':[{'current_key':'test-only-key'}]}]}
    def test_own_product(self):
        self.assertIn('applicationId=io.woowtech.agent\n',convert(self.doc))
    def test_rejects_other_product(self):
        self.doc['client'][0]['client_info']['android_client_info']['package_name']='io.woowtech.smart'
        with self.assertRaises(ValueError):convert(self.doc)
    def test_rejects_ambiguous_client(self):
        self.doc['client'].append(copy.deepcopy(self.doc['client'][0]))
        with self.assertRaises(ValueError):convert(self.doc)
    def test_rejects_injected_property(self):
        self.doc['project_info']['project_id']='test\napplicationId=other'
        with self.assertRaises(ValueError):convert(self.doc)
    def test_rejects_different_sender(self):
        self.doc['project_info']['project_number']='456'
        with self.assertRaises(ValueError):convert(self.doc)

if __name__=='__main__':unittest.main()
